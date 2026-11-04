<?php

namespace Tests\Feature;

use App\Models\ApiSession;
use App\Models\EncryptedAttachment;
use App\Models\PublicRecordSnapshot;
use App\Models\SyncOperation;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class CloudPrivacyTest extends TestCase
{
    use RefreshDatabase;

    private function connection(): array
    {
        $user = User::factory()->create();
        $device = $user->enrolledDevices()->create(['device_name' => 'Privacy test', 'platform' => 'ios']);
        $space = $user->syncedSpaces()->create(['id' => (string) Str::uuid(), 'storage_mode' => 'arca_sync', 'current_key_version' => 1]);
        $this->withToken(ApiSession::issue($user, $device->id));

        return [$user, $device, $space];
    }

    private function operation($user, $device, $space, string $collectionId): SyncOperation
    {
        return SyncOperation::create([
            'operation_id' => (string) Str::uuid(), 'space_id' => $space->id, 'user_id' => $user->id,
            'device_id' => $device->id, 'entity_id' => (string) Str::uuid(), 'entity_type' => 'record',
            'base_revision' => 0, 'new_revision' => 1, 'key_version' => 1, 'schema_version' => 1, 'ciphertext_bytes' => 10,
            'encrypted_envelope_json' => ['operation' => ['collectionId' => $collectionId, 'encryptedEnvelope' => ['ciphertextBase64' => 'sealed']]],
        ]);
    }

    private function policy(string $collectionId, int $cursor): array
    {
        return ['expected_cursor' => $cursor, 'generation' => 0, 'rule' => [
            'collectionId' => $collectionId, 'changeId' => (string) Str::uuid(), 'keyGeneration' => 1,
            'envelope' => ['ciphertextBase64' => 'sealed-rule', 'keyId' => (string) Str::uuid()],
        ]];
    }

    public function test_scoped_removal_preserves_other_collection_and_is_idempotent(): void
    {
        [$user, $device, $space] = $this->connection();
        $private = (string) Str::uuid();
        $removed = $this->operation($user, $device, $space, $private);
        $retained = $this->operation($user, $device, $space, (string) Str::uuid());
        $privateShare = PublicRecordSnapshot::create(['user_id' => $user->id, 'space_id' => $space->id, 'record_id' => $removed->entity_id, 'share_token' => 'private-share', 'selected_fields_json' => ['Secret' => 'private']]);
        $otherShare = PublicRecordSnapshot::create(['user_id' => $user->id, 'space_id' => $space->id, 'record_id' => $retained->entity_id, 'share_token' => 'other-share', 'selected_fields_json' => ['Other' => 'ordinary']]);
        $payload = $this->policy($private, $retained->server_cursor);
        $this->postJson("/api/v1/spaces/{$space->id}/privacy", $payload)->assertOk()->assertJsonPath('verified', true)->assertJsonPath('generation', 1);
        $this->assertDatabaseMissing('sync_operations', ['operation_id' => $removed->operation_id]);
        $this->assertDatabaseHas('sync_operations', ['operation_id' => $retained->operation_id]);
        $this->assertDatabaseMissing('public_record_snapshots', ['id' => $privateShare->id]);
        $this->assertDatabaseHas('public_record_snapshots', ['id' => $otherShare->id]);
        $this->postJson('/api/v1/snapshots', ['space_id' => $space->id, 'record_id' => $retained->entity_id, 'selected_fields' => ['unsafe' => 'value']])->assertConflict();
        $later = $this->operation($user, $device, $space, $private);
        $this->postJson("/api/v1/spaces/{$space->id}/privacy", $payload)->assertOk()->assertJsonPath('generation', 1);
        $this->assertDatabaseHas('sync_operations', ['operation_id' => $later->operation_id]);
        $this->getJson("/api/v1/spaces/{$space->id}/privacy")->assertOk()->assertJsonPath('rules.0.changeId', $payload['rule']['changeId']);
    }

    public function test_concurrent_remote_edit_and_legacy_routing_leave_deletion_unacknowledged(): void
    {
        [$user, $device, $space] = $this->connection();
        $collection = (string) Str::uuid();
        $op = $this->operation($user, $device, $space, $collection);
        $this->postJson("/api/v1/spaces/{$space->id}/privacy", $this->policy($collection, 0))->assertConflict();
        $op->encrypted_envelope_json = ['ciphertextBase64' => 'legacy'];
        $op->save();
        $this->postJson("/api/v1/spaces/{$space->id}/privacy", $this->policy($collection, $op->server_cursor))->assertConflict();
        $this->assertDatabaseHas('sync_operations', ['operation_id' => $op->operation_id]);
        $this->assertSame(0, $space->fresh()->privacy_generation);
    }

    public function test_old_and_stale_clients_cannot_republish_after_acknowledged_removal(): void
    {
        [$user, $device, $space] = $this->connection();
        $collection = (string) Str::uuid();
        $this->postJson("/api/v1/spaces/{$space->id}/privacy", $this->policy($collection, 0))->assertOk();
        $op = ['operation_id' => (string) Str::uuid(), 'entity_id' => (string) Str::uuid(), 'entity_type' => 'record',
            'new_revision' => 1, 'key_version' => 1, 'schema_version' => 1, 'ciphertext_bytes' => 10,
            'encrypted_envelope' => ['operation' => ['collectionId' => $collection, 'encryptedEnvelope' => ['ciphertextBase64' => 'sealed']]]];
        $this->postJson("/api/v1/spaces/{$space->id}/push", ['operations' => [$op]])->assertConflict();
        $this->postJson("/api/v1/spaces/{$space->id}/push", ['operations' => [$op], 'privacy_protocol' => 1, 'privacy_generation' => 0])->assertConflict();
        $this->postJson("/api/v1/spaces/{$space->id}/push", ['operations' => [$op], 'privacy_protocol' => 1, 'privacy_generation' => 1])->assertOk();
    }

    public function test_attachment_object_prevents_false_deletion_receipt(): void
    {
        [$user, $device, $space] = $this->connection();
        $collection = (string) Str::uuid();
        $op = $this->operation($user, $device, $space, $collection);
        EncryptedAttachment::create(['id' => (string) Str::uuid(), 'space_id' => $space->id, 'user_id' => $user->id,
            'record_id' => $op->entity_id, 'byte_size' => 20, 'ciphertext_sha256' => str_repeat('a', 64),
            'storage_disk' => 'local', 'object_key' => 'unverified-object', 'key_version' => 1]);
        $this->postJson("/api/v1/spaces/{$space->id}/privacy", $this->policy($collection, $op->server_cursor))->assertConflict();
        $this->assertDatabaseHas('sync_operations', ['operation_id' => $op->operation_id]);
    }
}
