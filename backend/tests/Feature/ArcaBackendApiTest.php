<?php

namespace Tests\Feature;

use App\Models\AppAnnouncement;
use App\Models\EncryptedAttachment;
use App\Models\EnrolledDevice;
use App\Models\PublicRecordSnapshot;
use App\Models\SyncedSpace;
use App\Models\SyncOperation;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class ArcaBackendApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_account_deletion_removes_devices_and_invalidates_the_token(): void
    {
        $user = User::factory()->create();
        $device = $user->enrolledDevices()->create(['device_name' => 'iPhone', 'platform' => 'ios']);
        $this->withToken($user->api_token)->deleteJson('/api/v1/account')
            ->assertOk()->assertJsonPath('didDeleteEntireAccount', true);
        $this->assertDatabaseMissing('users', ['id' => $user->id]);
        $this->assertDatabaseMissing('enrolled_devices', ['id' => $device->id]);
        $this->getJson('/api/v1/auth/me')->assertUnauthorized();
    }

    public function test_another_account_cannot_claim_or_rekey_a_registered_device(): void
    {
        $owner = User::factory()->create();
        $attacker = User::factory()->create();
        $device = $owner->enrolledDevices()->create(['device_name' => 'iPhone', 'platform' => 'ios', 'public_key_x25519' => 'original']);
        $body = ['id' => $device->id, 'device_token' => 'untrusted', 'device_name' => 'other', 'platform' => 'ios', 'public_key_x25519' => 'new'];
        $this->postJson('/api/v1/devices/register', $body)->assertForbidden();
        $this->withToken($attacker->api_token)->postJson('/api/v1/devices/enroll', $body)->assertForbidden();
        $this->assertSame('original', $device->fresh()->public_key_x25519);
        $this->assertSame($owner->id, $device->fresh()->user_id);
    }

    /**
     * 1. User registration, login, and default arca_sync storage mode config.
     */
    public function test_user_registration_login_and_default_arca_sync_storage_mode(): void
    {
        // Register user
        $registerResponse = $this->postJson('/api/v1/auth/register', [
            'name' => 'Alice Test',
            'email' => 'alice@arca.app',
            'password' => 'SecurePass123!',
        ]);

        $registerResponse->assertStatus(201)
            ->assertJsonPath('user.email', 'alice@arca.app')
            ->assertJsonPath('user.subscription_tier', 'free')
            ->assertJsonPath('default_space_storage_mode', 'arca_sync')
            ->assertJsonPath('entitlements.max_devices', 2)
            ->assertJsonPath('entitlements.max_storage_bytes', 262144000)
            ->assertJsonStructure([
                'user' => ['id', 'uuid', 'name', 'email', 'subscription_tier', 'subscription_state'],
                'api_token',
                'default_space_storage_mode',
                'entitlements',
                'post_expiry_policy',
            ]);

        $apiToken = $registerResponse->json('api_token');
        $this->assertNotEmpty($apiToken);

        // Login with credentials
        $loginResponse = $this->postJson('/api/v1/auth/login', [
            'email' => 'alice@arca.app',
            'password' => 'SecurePass123!',
        ]);

        $loginResponse->assertStatus(200)
            ->assertJsonPath('user.email', 'alice@arca.app')
            ->assertJsonPath('default_space_storage_mode', 'arca_sync');

        // Test auth/me with Bearer token
        $meResponse = $this->withHeader('Authorization', "Bearer {$apiToken}")
            ->getJson('/api/v1/auth/me');

        $meResponse->assertStatus(200)
            ->assertJsonPath('user.email', 'alice@arca.app')
            ->assertJsonPath('default_space_storage_mode', 'arca_sync')
            ->assertJsonPath('entitlements.tier', 'free')
            ->assertJsonPath('entitlements.max_devices', 2);
    }

    /**
     * 2. Device enrollment & Free-tier 2-device limit vs Pro-tier 10-device limit
     *    + device revocation rotating current_key_version on spaces.
     */
    public function test_device_enrollment_and_quota_limits_and_revocation_key_rotation(): void
    {
        $user = User::factory()->create([
            'subscription_tier' => 'free',
            'subscription_state' => 'active',
        ]);
        $token = $user->api_token;

        $authHeader = ['Authorization' => "Bearer {$token}"];

        // Enroll device 1 (Free tier - 1st device)
        $device1Id = (string) Str::uuid();
        $resp1 = $this->withHeaders($authHeader)->postJson('/api/v1/devices/enroll', [
            'id' => $device1Id,
            'device_name' => 'Alice iPhone 16 Pro',
            'platform' => 'ios',
            'public_key_x25519' => 'x25519_pub_key_base64_sample_device_1',
        ]);
        $resp1->assertStatus(201)
            ->assertJsonPath('device.id', $device1Id);

        // Enroll device 2 (Free tier - 2nd device)
        $device2Id = (string) Str::uuid();
        $resp2 = $this->withHeaders($authHeader)->postJson('/api/v1/devices/enroll', [
            'id' => $device2Id,
            'device_name' => 'Alice Pixel 9 Pro',
            'platform' => 'android',
            'public_key_x25519' => 'x25519_pub_key_base64_sample_device_2',
        ]);
        $resp2->assertStatus(201);

        // Attempt device 3 on Free tier (Should be rejected with 403 DEVICE_LIMIT_EXCEEDED)
        $device3Id = (string) Str::uuid();
        $resp3 = $this->withHeaders($authHeader)->postJson('/api/v1/devices/enroll', [
            'id' => $device3Id,
            'device_name' => 'Alice MacBook M3',
            'platform' => 'macos',
            'public_key_x25519' => 'x25519_pub_key_base64_sample_device_3',
        ]);
        $resp3->assertStatus(403)
            ->assertJsonPath('error_code', 'DEVICE_LIMIT_EXCEEDED')
            ->assertJsonPath('max_allowed_devices', 2)
            ->assertJsonPath('active_devices_count', 2);

        // Upgrade user to Pro tier (Pro allows up to 10 devices)
        $user->update(['subscription_tier' => 'pro']);

        // Now device 3 enrollment succeeds
        $resp3Pro = $this->withHeaders($authHeader)->postJson('/api/v1/devices/enroll', [
            'id' => $device3Id,
            'device_name' => 'Alice MacBook M3',
            'platform' => 'macos',
            'public_key_x25519' => 'x25519_pub_key_base64_sample_device_3',
        ]);
        $resp3Pro->assertStatus(201);

        // Create a Synced Space in arca_sync mode with current_key_version = 1
        $spaceId = (string) Str::uuid();
        $this->withHeaders($authHeader)->postJson("/api/v1/spaces/{$spaceId}/register", [
            'storage_mode' => 'arca_sync',
            'current_key_version' => 1,
        ])->assertStatus(200);

        $space = SyncedSpace::find($spaceId);
        $this->assertEquals(1, $space->current_key_version);

        // Revoke device 1
        $revokeResp = $this->withHeaders($authHeader)->postJson("/api/v1/devices/{$device1Id}/revoke");
        $revokeResp->assertStatus(200)
            ->assertJsonPath('message', 'Device revoked successfully and space key versions rotated.');

        // Verify device 1 is revoked and space key version rotated to 2
        $this->assertNotNull(EnrolledDevice::find($device1Id)->revoked_at);
        $space->refresh();
        $this->assertEquals(2, $space->current_key_version);
    }

    /**
     * 3. E2EE Sync push & pull, operation idempotency, and zero-plaintext validation.
     */
    public function test_e2ee_sync_push_and_pull_idempotency_and_zero_plaintext_validation(): void
    {
        $user = User::factory()->create([
            'subscription_tier' => 'free',
            'subscription_state' => 'active',
        ]);
        $token = $user->api_token;
        $deviceId = (string) Str::uuid();
        $spaceId = (string) Str::uuid();

        EnrolledDevice::create([
            'id' => $deviceId,
            'user_id' => $user->id,
            'device_name' => 'Test Device',
            'platform' => 'ios',
            'public_key_x25519' => 'sample_pubkey',
        ]);

        $authHeaders = [
            'Authorization' => "Bearer {$token}",
            'X-Device-Id' => $deviceId,
        ];

        // 3a. Zero-plaintext violation: envelope contains forbidden plaintext keys ('plaintext')
        $leakyPushResp = $this->withHeaders($authHeaders)->postJson("/api/v1/spaces/{$spaceId}/push", [
            'operations' => [
                [
                    'operation_id' => (string) Str::uuid(),
                    'entity_id' => (string) Str::uuid(),
                    'entity_type' => 'record',
                    'base_revision' => null,
                    'new_revision' => 1,
                    'key_version' => 1,
                    'schema_version' => 1,
                    'ciphertext_bytes' => 128,
                    'encrypted_envelope' => [
                        'nonceBase64' => '9k8sF2+lQ==',
                        'ciphertextAndTagBase64' => '8F2kA+==',
                        'plaintext' => 'LEAKED_PASSWORD_PLAINTEXT', // FORBIDDEN!
                    ],
                ],
            ],
        ]);

        $leakyPushResp->assertStatus(422)
            ->assertJsonPath('error', 'ZERO_PLAINTEXT_VIOLATION');

        $this->assertEquals(0, SyncOperation::where('space_id', $spaceId)->count());

        // 3b. Push valid zero-knowledge E2EE envelopes
        $op1Id = (string) Str::uuid();
        $op2Id = (string) Str::uuid();
        $entity1Id = (string) Str::uuid();
        $entity2Id = (string) Str::uuid();

        $validPayload = [
            'operations' => [
                [
                    'operation_id' => $op1Id,
                    'entity_id' => $entity1Id,
                    'entity_type' => 'schema',
                    'base_revision' => null,
                    'new_revision' => 1,
                    'key_version' => 1,
                    'schema_version' => 1,
                    'ciphertext_bytes' => 256,
                    'encrypted_envelope' => [
                        'nonceBase64' => 'p+f8D3kA==',
                        'ciphertextAndTagBase64' => 'mK9zR7vP1L==',
                        'aadSummary' => 'schema_definition_v1',
                    ],
                ],
                [
                    'operation_id' => $op2Id,
                    'entity_id' => $entity2Id,
                    'entity_type' => 'record',
                    'base_revision' => null,
                    'new_revision' => 1,
                    'key_version' => 1,
                    'schema_version' => 1,
                    'ciphertext_bytes' => 512,
                    'encrypted_envelope' => [
                        'nonceBase64' => 'a+1B3C4D==',
                        'ciphertextAndTagBase64' => 'xY78Z9wQ==',
                        'aadSummary' => 'encrypted_record_v1',
                    ],
                ],
            ],
        ];

        $pushResp = $this->withHeaders($authHeaders)->postJson("/api/v1/spaces/{$spaceId}/push", $validPayload);
        $pushResp->assertStatus(200)
            ->assertJsonPath('space_id', $spaceId)
            ->assertJsonPath('operations_processed', 2)
            ->assertJsonPath('acknowledged_operation_ids', [$op1Id, $op2Id]);

        $this->assertEquals(2, SyncOperation::where('space_id', $spaceId)->count());

        // 3c. Idempotency test: push same payload again
        $idempotentResp = $this->withHeaders($authHeaders)->postJson("/api/v1/spaces/{$spaceId}/push", $validPayload);
        $idempotentResp->assertStatus(200)
            ->assertJsonPath('acknowledged_operation_ids', [$op1Id, $op2Id]);

        // Still only 2 rows in database (no duplicates!)
        $this->assertEquals(2, SyncOperation::where('space_id', $spaceId)->count());

        // 3d. Pull operations
        $pullResp = $this->withHeaders($authHeaders)->getJson("/api/v1/spaces/{$spaceId}/pull?since_cursor=0");
        $pullResp->assertStatus(200)
            ->assertJsonPath('space_id', $spaceId)
            ->assertJsonPath('since_cursor', 0)
            ->assertJsonCount(2, 'operations');

        $latestCursor = $pullResp->json('latest_cursor');
        $this->assertGreaterThan(0, $latestCursor);

        // Pull with since_cursor = latestCursor (returns 0 new operations)
        $pullEmptyResp = $this->withHeaders($authHeaders)->getJson("/api/v1/spaces/{$spaceId}/pull?since_cursor={$latestCursor}");
        $pullEmptyResp->assertStatus(200)
            ->assertJsonCount(0, 'operations');
    }

    /**
     * 4. Switching Space mode from arca_sync (Cloud DB default) to local_only
     *    with verified remote ciphertext deletion receipt (verified_zero_remaining == true).
     */
    public function test_switching_space_mode_from_arca_sync_to_local_only_with_remote_deletion_receipt(): void
    {
        $user = User::factory()->create([
            'remote_storage_bytes_used' => 2048,
        ]);
        $token = $user->api_token;
        $deviceId = (string) Str::uuid();
        $spaceId = (string) Str::uuid();

        EnrolledDevice::create([
            'id' => $deviceId,
            'user_id' => $user->id,
            'device_name' => 'Device 1',
            'platform' => 'ios',
            'public_key_x25519' => 'pubkey',
        ]);

        $space = SyncedSpace::create([
            'id' => $spaceId,
            'user_id' => $user->id,
            'storage_mode' => 'arca_sync',
            'ciphertext_bytes' => 2048,
        ]);

        // Create 2 sync operations
        SyncOperation::create([
            'operation_id' => (string) Str::uuid(),
            'space_id' => $spaceId,
            'user_id' => $user->id,
            'device_id' => $deviceId,
            'entity_id' => (string) Str::uuid(),
            'entity_type' => 'record',
            'new_revision' => 1,
            'key_version' => 1,
            'schema_version' => 1,
            'ciphertext_bytes' => 1024,
            'encrypted_envelope_json' => ['nonce' => 'abc', 'ciphertext' => 'def'],
        ]);

        SyncOperation::create([
            'operation_id' => (string) Str::uuid(),
            'space_id' => $spaceId,
            'user_id' => $user->id,
            'device_id' => $deviceId,
            'entity_id' => (string) Str::uuid(),
            'entity_type' => 'record',
            'new_revision' => 2,
            'key_version' => 1,
            'schema_version' => 1,
            'ciphertext_bytes' => 1024,
            'encrypted_envelope_json' => ['nonce' => 'ghi', 'ciphertext' => 'jkl'],
        ]);

        $this->assertEquals(2, SyncOperation::where('space_id', $spaceId)->count());

        // Migrate mode to local_only with remote ciphertext deletion
        $resp = $this->withHeader('Authorization', "Bearer {$token}")
            ->postJson("/api/v1/spaces/{$spaceId}/migrate-mode", [
                'target_mode' => 'local_only',
                'delete_remote_ciphertext' => true,
            ]);

        $resp->assertStatus(200)
            ->assertJsonPath('receipt.space_id', $spaceId)
            ->assertJsonPath('receipt.target_mode', 'local_only')
            ->assertJsonPath('receipt.deleted_operation_count', 2)
            ->assertJsonPath('receipt.freed_storage_bytes', 2048)
            ->assertJsonPath('receipt.verified_zero_remaining', true)
            ->assertJsonStructure([
                'message',
                'receipt' => [
                    'space_id',
                    'target_mode',
                    'deleted_operation_count',
                    'deleted_attachment_count',
                    'freed_storage_bytes',
                    'verified_zero_remaining',
                    'deleted_at',
                    'signature_sha256',
                ],
            ]);

        // Verify remote rows permanently removed
        $this->assertEquals(0, SyncOperation::where('space_id', $spaceId)->count());
        $space->refresh();
        $this->assertEquals('local_only', $space->storage_mode);
        $this->assertEquals(0, $space->ciphertext_bytes);
    }

    /**
     * 5. RevenueCat webhook lifecycle (INITIAL_PURCHASE -> Pro active,
     *    BILLING_ISSUE -> grace period, EXPIRATION -> Free expired with push paused
     *    when over quota, while pull remains allowed).
     */
    public function test_revenuecat_webhook_lifecycle_and_quota_enforcement(): void
    {
        $user = User::factory()->create([
            'subscription_tier' => 'free',
            'subscription_state' => 'active',
            'remote_storage_bytes_used' => 0,
        ]);
        $webhookSecret = 'webhook-test-only';
        config(['arca.revenuecat.webhook_secret' => $webhookSecret]);
        $webhookHeader = ['Authorization' => "Bearer {$webhookSecret}"];

        // 5a. INITIAL_PURCHASE webhook -> upgrades to Pro active
        $purchaseResp = $this->withHeaders($webhookHeader)->postJson('/api/v1/webhooks/revenuecat', [
            'event' => [
                'id' => (string) Str::uuid(),
                'type' => 'INITIAL_PURCHASE',
                'app_user_id' => $user->uuid,
                'product_id' => 'arca_pro_monthly',
                'expiration_at_ms' => now()->addMonth()->timestamp * 1000,
            ],
        ]);

        $purchaseResp->assertStatus(200)
            ->assertJsonPath('status', 'success');

        $user->refresh();
        $this->assertEquals('pro', $user->subscription_tier);
        $this->assertEquals('active', $user->subscription_state);
        $this->assertEquals('arca_pro_monthly', $user->subscription_product_id);

        // 5b. BILLING_ISSUE webhook -> transitions to billing_grace_period
        $billingResp = $this->withHeaders($webhookHeader)->postJson('/api/v1/webhooks/revenuecat', [
            'event' => [
                'id' => (string) Str::uuid(),
                'type' => 'BILLING_ISSUE',
                'app_user_id' => $user->uuid,
                'product_id' => 'arca_pro_monthly',
            ],
        ]);

        $billingResp->assertStatus(200);
        $user->refresh();
        $this->assertEquals('pro', $user->subscription_tier);
        $this->assertEquals('billing_grace_period', $user->subscription_state);

        // 5c. EXPIRATION webhook -> transitions back to free expired
        $expResp = $this->withHeaders($webhookHeader)->postJson('/api/v1/webhooks/revenuecat', [
            'event' => [
                'id' => (string) Str::uuid(),
                'type' => 'EXPIRATION',
                'app_user_id' => $user->uuid,
            ],
        ]);

        $expResp->assertStatus(200);
        $user->refresh();
        $this->assertEquals('free', $user->subscription_tier);
        $this->assertEquals('expired', $user->subscription_state);

        // Verify post expiry policy
        $policy = $user->postExpiryPolicy();
        $this->assertTrue($policy['canPullRemoteSync']); // Pull is allowed!
        $this->assertFalse($policy['canPushRemoteSync']); // Push is paused!
        $this->assertTrue($policy['canLocalRead']);
        $this->assertTrue($policy['canLocalWrite']);
        $this->assertTrue($policy['canLocalExport']);

        // Test pushing while expired: returns 403 SUBSCRIPTION_EXPIRED_PUSH_PAUSED
        $deviceId = (string) Str::uuid();
        EnrolledDevice::create([
            'id' => $deviceId,
            'user_id' => $user->id,
            'device_name' => 'Device Expired',
            'platform' => 'ios',
            'public_key_x25519' => 'pubkey',
        ]);
        $spaceId = (string) Str::uuid();

        $pushWhileExpired = $this->withHeaders([
            'Authorization' => "Bearer {$user->api_token}",
            'X-Device-Id' => $deviceId,
        ])->postJson("/api/v1/spaces/{$spaceId}/push", [
            'operations' => [
                [
                    'operation_id' => (string) Str::uuid(),
                    'entity_id' => (string) Str::uuid(),
                    'entity_type' => 'record',
                    'new_revision' => 1,
                    'key_version' => 1,
                    'schema_version' => 1,
                    'ciphertext_bytes' => 100,
                    'encrypted_envelope' => [
                        'nonce' => 'abc',
                        'ciphertext' => 'def',
                    ],
                ],
            ],
        ]);

        $pushWhileExpired->assertStatus(403)
            ->assertJsonPath('error_code', 'SUBSCRIPTION_EXPIRED_PUSH_PAUSED')
            ->assertJsonPath('canLocalRead', true)
            ->assertJsonPath('canLocalWrite', true)
            ->assertJsonPath('canLocalExport', true);

        // Test pulling while expired: returns 200 OK
        $pullWhileExpired = $this->withHeader('Authorization', "Bearer {$user->api_token}")
            ->getJson("/api/v1/spaces/{$spaceId}/pull?since_cursor=0");

        $pullWhileExpired->assertStatus(200);
    }

    /**
     * 6. App Announcements / Ads feed filtering by platform & tier,
     *    plus /admin dashboard rendering and announcement creation.
     */
    public function test_app_announcements_feed_filtering_and_admin_dashboard(): void
    {
        // Create sample announcements
        AppAnnouncement::create([
            'title' => 'iOS Free Promo',
            'body' => 'Exclusive for iOS Free users',
            'placement' => 'home_banner',
            'target_platform' => 'ios',
            'target_tier' => 'free',
            'is_active' => true,
            'priority' => 10,
        ]);

        AppAnnouncement::create([
            'title' => 'Android Pro Feature',
            'body' => 'Exclusive for Android Pro users',
            'placement' => 'settings_card',
            'target_platform' => 'android',
            'target_tier' => 'pro',
            'is_active' => true,
            'priority' => 5,
        ]);

        AppAnnouncement::create([
            'title' => 'Universal Announcement',
            'body' => 'For everyone across all platforms',
            'placement' => 'announcement_modal',
            'target_platform' => 'all',
            'target_tier' => 'all',
            'is_active' => true,
            'priority' => 1,
        ]);

        AppAnnouncement::create([
            'title' => 'Inactive Announcement',
            'body' => 'Should not appear anywhere',
            'placement' => 'home_banner',
            'target_platform' => 'all',
            'target_tier' => 'all',
            'is_active' => false,
            'priority' => 1,
        ]);

        // 6a. Filter feed for iOS + Free
        $iosFreeResp = $this->getJson('/api/v1/app-feed?platform=ios&tier=free');
        $iosFreeResp->assertStatus(200)
            ->assertJsonPath('remote_config.default_space_storage_mode', 'arca_sync')
            ->assertJsonPath('remote_config.local_only_available', true);

        $titles = collect($iosFreeResp->json('announcements'))->pluck('title')->all();
        $this->assertContains('iOS Free Promo', $titles);
        $this->assertContains('Universal Announcement', $titles);
        $this->assertNotContains('Android Pro Feature', $titles);
        $this->assertNotContains('Inactive Announcement', $titles);

        // 6b. Filter feed for Android + Pro
        $androidProResp = $this->getJson('/api/v1/app-feed?platform=android&tier=pro');
        $androidProResp->assertStatus(200);
        $androidTitles = collect($androidProResp->json('announcements'))->pluck('title')->all();
        $this->assertContains('Android Pro Feature', $androidTitles);
        $this->assertContains('Universal Announcement', $androidTitles);
        $this->assertNotContains('iOS Free Promo', $androidTitles);

        // 6c. Admin dashboard rendering
        $this->getJson('/admin')->assertUnauthorized();
        $this->actingAs(User::factory()->create())->getJson('/admin')->assertForbidden();
        $admin = User::factory()->create(['is_admin' => true]);
        $this->actingAs($admin);
        $adminResp = $this->get('/admin');
        $adminResp->assertStatus(200)
            ->assertSee('Arca System Administration')
            ->assertSee('E2EE Zero-Knowledge Verified')
            ->assertSee('Total Users')
            ->assertSee('Pro Subscribers')
            ->assertSee('Enrolled Devices')
            ->assertSee('Synced Spaces')
            ->assertSee('Opaque Ciphertext Stored');

        // 6d. Admin announcement creation via POST /admin/announcements
        $createAnnResp = $this->post('/admin/announcements', [
            'title' => 'Admin Special Notice',
            'body' => 'Notice posted from the web dashboard',
            'cta_label' => 'Click Here',
            'cta_url' => 'https://arca.app',
            'placement' => 'home_banner',
            'target_platform' => 'all',
            'target_tier' => 'all',
            'priority' => 100,
            'is_active' => 1,
        ]);
        $createAnnResp->assertRedirect('/admin');

        $created = AppAnnouncement::where('title', 'Admin Special Notice')->first();
        $this->assertNotNull($created);
        $this->assertTrue($created->is_active);

        // 6e. Toggle announcement active status via POST /admin/announcements/{id}/toggle
        $toggleResp = $this->post("/admin/announcements/{$created->id}/toggle");
        $toggleResp->assertRedirect('/admin');

        $created->refresh();
        $this->assertFalse($created->is_active);
    }

    /**
     * 7. Revocable public record snapshot creation, viewing, and immediate revocation (410 Gone).
     */
    public function test_revocable_public_record_snapshots_lifecycle_and_revocation(): void
    {
        $user = User::factory()->create();
        $authHeader = ['Authorization' => "Bearer {$user->api_token}"];

        $spaceId = (string) Str::uuid();
        $recordId = (string) Str::uuid();

        // 7a. Create public record snapshot
        $createResp = $this->withHeaders($authHeader)->postJson('/api/v1/snapshots', [
            'space_id' => $spaceId,
            'record_id' => $recordId,
            'selected_fields' => [
                'title' => 'COVID-19 Vaccination Record',
                'type' => 'Medical',
                'dose_date' => '2024-05-12',
            ],
            'expires_at' => now()->addDays(7)->toIso8601String(),
        ]);

        $createResp->assertStatus(201)
            ->assertJsonPath('snapshot.space_id', $spaceId)
            ->assertJsonPath('snapshot.record_id', $recordId)
            ->assertJsonStructure(['share_token', 'share_url', 'snapshot']);

        $shareToken = $createResp->json('share_token');
        $this->assertNotEmpty($shareToken);

        // 7b. Anonymous public viewing
        $viewResp = $this->getJson("/api/v1/snapshots/{$shareToken}");
        $viewResp->assertStatus(200)
            ->assertJsonPath('space_id', $spaceId)
            ->assertJsonPath('record_id', $recordId)
            ->assertJsonPath('selected_fields.title', 'COVID-19 Vaccination Record');

        // 7c. Revoke snapshot
        $revokeResp = $this->withHeaders($authHeader)->postJson("/api/v1/snapshots/{$shareToken}/revoke");
        $revokeResp->assertStatus(200)
            ->assertJsonPath('message', 'Snapshot successfully revoked.')
            ->assertJsonPath('share_token', $shareToken);

        $snapshot = PublicRecordSnapshot::where('share_token', $shareToken)->first();
        $this->assertNotNull($snapshot->revoked_at);

        // 7d. Anonymous viewing after revocation -> 410 Gone
        $viewAfterRevoke = $this->getJson("/api/v1/snapshots/{$shareToken}");
        $viewAfterRevoke->assertStatus(410)
            ->assertJsonPath('error', 'SNAPSHOT_REVOKED_OR_EXPIRED')
            ->assertJsonPath('revoked', true);
    }

    /**
     * 8. Encrypted attachment metadata registration and quota enforcement.
     */
    public function test_encrypted_attachment_registration_and_quota(): void
    {
        $user = User::factory()->create([
            'subscription_tier' => 'free',
            'remote_storage_bytes_used' => 0,
        ]);
        $token = $user->api_token;
        $authHeader = ['Authorization' => "Bearer {$token}"];

        $spaceId = (string) Str::uuid();
        $recordId = (string) Str::uuid();
        $attId = (string) Str::uuid();

        // 8a. Store attachment metadata
        $storeResp = $this->withHeaders($authHeader)->postJson("/api/v1/spaces/{$spaceId}/attachments", [
            'id' => $attId,
            'record_id' => $recordId,
            'byte_size' => 1048576, // 1 MB
            'ciphertext_sha256' => 'sample_sha256_hash_value',
            'key_version' => 1,
        ]);

        $storeResp->assertStatus(201)
            ->assertJsonPath('attachment.id', $attId)
            ->assertJsonStructure(['upload_url', 'attachment', 'object_key']);

        $user->refresh();
        $this->assertEquals(1048576, $user->remote_storage_bytes_used);

        // 8b. Retrieve attachment download URL
        $getResp = $this->withHeaders($authHeader)->getJson("/api/v1/spaces/{$spaceId}/attachments/{$attId}");
        $getResp->assertStatus(200)
            ->assertJsonPath('attachment.id', $attId)
            ->assertJsonPath('ciphertext_sha256', 'sample_sha256_hash_value')
            ->assertJsonStructure(['download_url']);

        // 8c. Test storage quota exceeded
        $user->update(['remote_storage_bytes_used' => $user->maxAllowedStorageBytes()]);
        $overQuotaResp = $this->withHeaders($authHeader)->postJson("/api/v1/spaces/{$spaceId}/attachments", [
            'id' => (string) Str::uuid(),
            'record_id' => $recordId,
            'byte_size' => 1024,
            'ciphertext_sha256' => 'hash',
        ]);
        $overQuotaResp->assertStatus(403)
            ->assertJsonPath('error', 'REMOTE_STORAGE_QUOTA_EXCEEDED');
    }

    /**
     * 9. Anonymous device registration with nullable user_id, device_token, and automatic login/registration association.
     */
    public function test_anonymous_device_registration_with_nullable_user_id_and_login_association(): void
    {
        $deviceId = (string) Str::uuid();
        $deviceToken = 'tok-android-pixel9-xyz';

        // 9a. Call POST /api/v1/devices/register without authentication
        $registerDeviceResp = $this->postJson('/api/v1/devices/register', [
            'id' => $deviceId,
            'device_token' => $deviceToken,
            'device_name' => 'Pixel 9 Pro XL',
            'platform' => 'android',
            'app_version' => '1.2.0',
            'public_key_x25519' => 'x25519_base64_sample_key',
        ]);

        $registerDeviceResp->assertStatus(201)
            ->assertJsonPath('device.id', $deviceId)
            ->assertJsonPath('device.device_token', $deviceToken)
            ->assertJsonPath('device.user_id', null)
            ->assertJsonPath('device.is_associated', false);

        // Verify DB row exists with user_id = null and device_token
        $deviceInDb = EnrolledDevice::find($deviceId);
        $this->assertNotNull($deviceInDb);
        $this->assertNull($deviceInDb->user_id);
        $this->assertEquals($deviceToken, $deviceInDb->device_token);
        $this->assertEquals('Pixel 9 Pro XL', $deviceInDb->device_name);
        $this->assertEquals('android', $deviceInDb->platform);

        // 9b. Update anonymous device before login
        $updateDeviceResp = $this->postJson('/api/v1/devices/register', [
            'device_token' => $deviceToken,
            'device_name' => 'Pixel 9 Pro XL (Renamed)',
            'platform' => 'android',
        ]);

        $updateDeviceResp->assertStatus(200)
            ->assertJsonPath('device.device_name', 'Pixel 9 Pro XL (Renamed)')
            ->assertJsonPath('device.user_id', null);

        // 9c. Call POST /api/v1/auth/register passing device_id and device_token
        $registerUserResp = $this->postJson('/api/v1/auth/register', [
            'name' => 'Bob Mobile',
            'email' => 'bob.mobile@arca.app',
            'password' => 'BobMobilePassword123!',
            'device_id' => $deviceId,
            'device_token' => $deviceToken,
            'device_name' => 'Pixel 9 Pro XL (Renamed)',
            'platform' => 'android',
        ]);

        $registerUserResp->assertStatus(201)
            ->assertJsonPath('user.email', 'bob.mobile@arca.app')
            ->assertJsonPath('associated_device.id', $deviceId)
            ->assertJsonPath('associated_device.device_token', $deviceToken);

        $registeredUserId = $registerUserResp->json('user.id');
        $this->assertNotNull($registeredUserId);

        // Verify DB row now has user_id = $user->id
        $deviceInDb->refresh();
        $this->assertEquals($registeredUserId, $deviceInDb->user_id);
        $this->assertTrue($deviceInDb->is_associated);

        // 9d. Test login association with an anonymous iOS device
        $iosDeviceId = (string) Str::uuid();
        $iosDeviceToken = 'tok-ios-iphone16pro-abc';

        $this->postJson('/api/v1/devices/register', [
            'id' => $iosDeviceId,
            'device_token' => $iosDeviceToken,
            'device_name' => 'iPhone 16 Pro',
            'platform' => 'ios',
        ])->assertStatus(201);

        $loginResp = $this->postJson('/api/v1/auth/login', [
            'email' => 'bob.mobile@arca.app',
            'password' => 'BobMobilePassword123!',
            'device_id' => $iosDeviceId,
            'device_token' => $iosDeviceToken,
            'device_name' => 'iPhone 16 Pro',
            'platform' => 'ios',
        ]);

        $loginResp->assertStatus(200)
            ->assertJsonPath('associated_device.id', $iosDeviceId)
            ->assertJsonPath('associated_device.device_token', $iosDeviceToken);

        $iosDeviceInDb = EnrolledDevice::find($iosDeviceId);
        $this->assertEquals($registeredUserId, $iosDeviceInDb->user_id);

        // 9e. Test DeviceController@enroll claiming an anonymous device without primary key collision
        $macDeviceId = (string) Str::uuid();
        $macDeviceToken = 'tok-macos-m3-xyz';

        // Pre-register anonymously
        $this->postJson('/api/v1/devices/register', [
            'id' => $macDeviceId,
            'device_token' => $macDeviceToken,
            'device_name' => 'MacBook Pro M3',
            'platform' => 'macos',
        ])->assertStatus(201);

        // Free tier has 2 active devices (Pixel + iPhone); enrolling a 3rd will exceed quota
        $token = $registerUserResp->json('api_token');
        $overQuotaEnrollResp = $this->withHeader('Authorization', "Bearer {$token}")
            ->postJson('/api/v1/devices/enroll', [
                'id' => $macDeviceId,
                'device_token' => $macDeviceToken,
                'device_name' => 'MacBook Pro M3',
                'platform' => 'macos',
                'public_key_x25519' => 'sample_pubkey_mac',
            ]);

        $overQuotaEnrollResp->assertStatus(403)
            ->assertJsonPath('error_code', 'DEVICE_LIMIT_EXCEEDED');

        // Upgrade Bob to Pro tier (allows up to 10 devices)
        $bobUser = User::find($registeredUserId);
        $bobUser->update(['subscription_tier' => 'pro']);

        // Now claim anonymous device via /devices/enroll
        $claimResp = $this->withHeader('Authorization', "Bearer {$token}")
            ->postJson('/api/v1/devices/enroll', [
                'id' => $macDeviceId,
                'device_token' => $macDeviceToken,
                'device_name' => 'MacBook Pro M3',
                'platform' => 'macos',
                'public_key_x25519' => 'sample_pubkey_mac',
            ]);

        $claimResp->assertStatus(201)
            ->assertJsonPath('device.id', $macDeviceId)
            ->assertJsonPath('device.user_id', $registeredUserId);

        $macDeviceInDb = EnrolledDevice::find($macDeviceId);
        $this->assertEquals($registeredUserId, $macDeviceInDb->user_id);
    }
}
