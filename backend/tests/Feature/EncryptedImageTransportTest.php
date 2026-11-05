<?php

namespace Tests\Feature;

use App\Models\ApiSession;
use App\Models\EncryptedAttachment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class EncryptedImageTransportTest extends TestCase
{
    use RefreshDatabase;

    private function connection(): array
    {
        $user = User::factory()->create();
        $device = $user->enrolledDevices()->create(['device_name' => 'Image test', 'platform' => 'ios']);
        $space = $user->syncedSpaces()->create(['id' => (string) Str::uuid(), 'storage_mode' => 'arca_sync', 'current_key_version' => 1]);
        $this->withToken(ApiSession::issue($user, $device->id));

        return [$user, $device, $space];
    }

    private function payload($device, $space): array
    {
        $envelope = ['version' => 1, 'keyId' => (string) Str::uuid(), 'nonceBase64' => base64_encode(str_repeat('n', 12)),
            'ciphertextBase64' => base64_encode('opaque-encrypted-image'), 'tagBase64' => base64_encode(str_repeat('t', 16)), 'aadDescription' => 'attachment-data-v1'];

        return ['privacy_generation' => 0, 'blob' => [
            'attachmentId' => (string) Str::uuid(), 'spaceId' => $space->id, 'collectionId' => (string) Str::uuid(),
            'recordId' => (string) Str::uuid(), 'authorDeviceId' => $device->id, 'keyGeneration' => 1,
            'ciphertextSHA256Hex' => hash('sha256', $envelope['ciphertextBase64'].':'.$envelope['tagBase64']),
            'encryptedMetadataEnvelope' => $envelope, 'encryptedDataEnvelope' => $envelope, 'uploadedAt' => now()->toIso8601String(),
        ]];
    }

    public function test_encrypted_roundtrip_retry_and_tenant_isolation(): void
    {
        [$user, $device, $space] = $this->connection();
        $payload = $this->payload($device, $space);
        $url = "/api/v1/spaces/{$space->id}/attachments";
        $this->postJson($url, $payload)->assertCreated();
        $bytes = $user->fresh()->remote_storage_bytes_used;
        $this->assertGreaterThan(0, $bytes);
        $this->postJson($url, $payload)->assertCreated();
        $this->assertSame($bytes, $user->fresh()->remote_storage_bytes_used);
        $this->assertDatabaseCount('encrypted_attachments', 1);
        $this->getJson($url.'/'.$payload['blob']['attachmentId'])->assertOk()->assertJsonPath('blob', $payload['blob']);
        [, $otherDevice] = $this->connection();
        $this->getJson($url.'/'.$payload['blob']['attachmentId'])->assertNotFound();
        $payload['blob']['authorDeviceId'] = $otherDevice->id;
        $this->postJson($url, $payload)->assertNotFound();
    }

    public function test_rejects_bad_checksum_plaintext_wrong_space_stale_policy_and_revoked_device(): void
    {
        [$user, $device, $space] = $this->connection();
        $payload = $this->payload($device, $space);
        $url = "/api/v1/spaces/{$space->id}/attachments";
        $bad = $payload;
        $bad['blob']['ciphertextSHA256Hex'] = str_repeat('0', 64);
        $this->postJson($url, $bad)->assertStatus(422);
        $bad = $payload;
        $bad['blob']['filename'] = 'private recipe';
        $this->postJson($url, $bad)->assertUnprocessable();
        $bad = $payload;
        $bad['blob']['spaceId'] = (string) Str::uuid();
        $this->postJson($url, $bad)->assertStatus(422);
        $space->update(['privacy_generation' => 1]);
        $this->postJson($url, $payload)->assertConflict();
        $device->update(['revoked_at' => now()]);
        $this->postJson($url, $payload)->assertForbidden();
        $this->assertDatabaseCount('encrypted_attachments', 0);
    }

    public function test_scoped_privacy_deletion_removes_image_bytes_and_fences_old_uploads(): void
    {
        [$user, $device, $space] = $this->connection();
        $payload = $this->payload($device, $space);
        $url = "/api/v1/spaces/{$space->id}/attachments";
        $this->postJson($url, $payload)->assertCreated();
        $other = $this->payload($device, $space);
        $this->postJson($url, $other)->assertCreated();
        $this->postJson("/api/v1/spaces/{$space->id}/privacy", ['expected_cursor' => 0, 'generation' => 0, 'rule' => [
            'collectionId' => $payload['blob']['collectionId'], 'changeId' => (string) Str::uuid(), 'keyGeneration' => 1,
            'envelope' => ['ciphertextBase64' => 'sealed-rule', 'keyId' => (string) Str::uuid()],
        ]])->assertOk()->assertJsonPath('verified', true);
        $this->getJson($url.'/'.$payload['blob']['attachmentId'])->assertNotFound();
        $this->getJson($url.'/'.$other['blob']['attachmentId'])->assertOk();
        $this->postJson($url, $payload)->assertConflict();
        $this->assertSame(EncryptedAttachment::sum('byte_size'), $user->fresh()->remote_storage_bytes_used);
    }

    public function test_disabled_space_and_quota_block_upload_and_anonymous_access_is_refused(): void
    {
        [$user, $device, $space] = $this->connection();
        $payload = $this->payload($device, $space);
        $url = "/api/v1/spaces/{$space->id}/attachments";
        $space->update(['storage_mode' => 'local_only']);
        $this->postJson($url, $payload)->assertForbidden();
        $space->update(['storage_mode' => 'arca_sync']);
        $user->update(['remote_storage_bytes_used' => $user->maxAllowedStorageBytes()]);
        $this->postJson($url, $payload)->assertForbidden();
        $this->withToken('invalid')->postJson($url, $payload)->assertUnauthorized();
        $this->assertDatabaseCount('encrypted_attachments', 0);
    }
}
