<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class SyncKeyTransportTest extends TestCase
{
    use RefreshDatabase;

    public function test_recovery_is_first_writer_wins_and_available_before_device_enrollment(): void
    {
        $user = User::factory()->create();
        $device = $user->enrolledDevices()->create(['device_name' => 'A', 'platform' => 'ios']);
        $bundle = ['accountId' => $user->uuid, 'makKeyId' => (string) Str::uuid(), 'hkdfSaltBase64' => 'salt', 'wrappedMAKEnvelope' => ['ciphertextBase64' => 'sealed'], 'createdAt' => '2026-11-03T00:00:00Z'];
        $this->withToken($user->api_token)->withHeader('X-Device-Id', $device->id)
            ->postJson('/api/v1/sync/recovery', $bundle)->assertOk()->assertJsonPath('bundle', $bundle);
        $replacement = array_replace($bundle, ['makKeyId' => (string) Str::uuid()]);
        $this->postJson('/api/v1/sync/recovery', $replacement)->assertOk()->assertJsonPath('bundle', $bundle);
        $this->withHeader('X-Device-Id', 'not-enrolled')->getJson('/api/v1/sync/recovery')->assertOk()->assertJsonPath('bundle', $bundle);
        $this->assertSame($bundle, $user->fresh()->sync_recovery_bundle);
    }

    public function test_key_history_survives_rotation_and_conflicting_generation_is_rejected(): void
    {
        $user = User::factory()->create();
        $device = $user->enrolledDevices()->create(['device_name' => 'A', 'platform' => 'ios']);
        $spaceId = (string) Str::uuid();
        $key = ['spaceId' => $spaceId, 'keyId' => (string) Str::uuid(), 'keyGeneration' => 1, 'wrappedKeyEnvelope' => ['ciphertextBase64' => 'sealed']];
        $this->withToken($user->api_token)->withHeader('X-Device-Id', $device->id)->postJson("/api/v1/spaces/$spaceId/keys", $key)->assertOk();
        $this->postJson("/api/v1/spaces/$spaceId/keys", array_replace($key, ['keyId' => (string) Str::uuid()]))->assertConflict();
        $second = array_replace($key, ['keyGeneration' => 2, 'keyId' => (string) Str::uuid()]);
        $this->postJson("/api/v1/spaces/$spaceId/keys", $second)->assertOk();
        $this->getJson('/api/v1/spaces')->assertOk()->assertJsonPath('spaces.0.wrapped_space_keys_json', [$key, $second]);
    }

    public function test_space_reregistration_preserves_key_history_and_rejects_key_updates(): void
    {
        $user = User::factory()->create();
        $device = $user->enrolledDevices()->create(['device_name' => 'A', 'platform' => 'ios']);
        $spaceId = (string) Str::uuid();
        $key = ['spaceId' => $spaceId, 'keyId' => (string) Str::uuid(), 'keyGeneration' => 1, 'wrappedKeyEnvelope' => ['ciphertextBase64' => 'sealed']];
        $this->withToken($user->api_token)->withHeader('X-Device-Id', $device->id)->postJson("/api/v1/spaces/$spaceId/keys", $key)->assertOk();
        $second = array_replace($key, ['keyGeneration' => 2, 'keyId' => (string) Str::uuid()]);
        $this->postJson("/api/v1/spaces/$spaceId/keys", $second)->assertOk();

        $this->postJson("/api/v1/spaces/$spaceId/register", ['current_key_version' => 1])->assertOk()
            ->assertJsonPath('space.current_key_version', 2)
            ->assertJsonPath('space.wrapped_space_keys_json', [$key, $second]);
        $this->postJson("/api/v1/spaces/$spaceId/register", ['current_key_version' => 1, 'wrapped_space_keys_json' => [$key]])
            ->assertUnprocessable()->assertJsonValidationErrors(['wrapped_space_keys_json']);
        $space = $user->syncedSpaces()->findOrFail($spaceId);
        $this->assertSame(2, $space->current_key_version);
        $this->assertSame([$key, $second], $space->wrapped_space_keys_json);
    }

    public function test_other_accounts_and_revoked_devices_cannot_read_or_publish_keys(): void
    {
        $user = User::factory()->create();
        $device = $user->enrolledDevices()->create(['device_name' => 'A', 'platform' => 'ios', 'revoked_at' => now()]);
        $this->withToken($user->api_token)->withHeader('X-Device-Id', $device->id)->getJson('/api/v1/spaces')->assertForbidden();
        $this->postJson('/api/v1/sync/recovery', [])->assertForbidden();
        $this->withToken('invalid')->getJson('/api/v1/sync/recovery')->assertUnauthorized();
    }
}
