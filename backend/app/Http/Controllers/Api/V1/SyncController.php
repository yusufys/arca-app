<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\EncryptedAttachment;
use App\Models\PublicRecordSnapshot;
use App\Models\SyncedSpace;
use App\Models\SyncOperation;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SyncController extends Controller
{
    private const FORBIDDEN_PLAINTEXT_KEYS = [
        'plaintext',
        'fields',
        'record_title',
        'title',
        'data',
        'body',
        'content',
        'unencrypted',
        'notes',
    ];

    private function authorizeDevice(Request $request): void
    {
        $deviceId = $request->header('X-Device-Id');
        abort_unless($deviceId && $request->user()->enrolledDevices()->whereKey($deviceId)->whereNull('revoked_at')->exists(), 403);
    }

    public function index(Request $request): JsonResponse
    {
        $this->authorizeDevice($request);

        return response()->json(['spaces' => $request->user()->syncedSpaces()->where('storage_mode', 'arca_sync')->orderBy('id')->get()]);
    }

    public function recovery(Request $request): JsonResponse
    {
        return response()->json(['bundle' => $request->user()->sync_recovery_bundle]);
    }

    public function storeRecovery(Request $request): JsonResponse
    {
        $this->authorizeDevice($request);
        $validated = $request->validate([
            'accountId' => 'required|uuid', 'makKeyId' => 'required|uuid',
            'hkdfSaltBase64' => 'required|string|max:1024', 'wrappedMAKEnvelope' => 'required|array',
            'createdAt' => 'required|date',
        ]);
        abort_unless(strcasecmp($validated['accountId'], $request->user()->uuid) === 0, 403);
        abort_if($this->findPlaintextViolation($validated['wrappedMAKEnvelope']) !== null, 422);

        return DB::transaction(function () use ($request, $validated) {
            $user = User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();
            if ($user->sync_recovery_bundle === null) {
                $user->sync_recovery_bundle = $validated;
                $user->save();
            }

            return response()->json(['bundle' => $user->sync_recovery_bundle]);
        });
    }

    public function keys(Request $request, string $spaceId): JsonResponse
    {
        $this->authorizeDevice($request);
        $space = $request->user()->syncedSpaces()->whereKey($spaceId)->first();
        $keys = $space?->wrapped_space_keys_json ?? [];

        return response()->json(['key' => $keys === [] ? null : $keys[count($keys) - 1]]);
    }

    public function storeKey(Request $request, string $spaceId): JsonResponse
    {
        $this->authorizeDevice($request);
        $validated = $request->validate([
            'spaceId' => 'required|uuid', 'keyId' => 'required|uuid',
            'keyGeneration' => 'required|integer|min:1', 'wrappedKeyEnvelope' => 'required|array',
        ]);
        abort_unless(strcasecmp($validated['spaceId'], $spaceId) === 0, 422);
        abort_if($this->findPlaintextViolation($validated['wrappedKeyEnvelope']) !== null, 422);

        return DB::transaction(function () use ($request, $validated, $spaceId) {
            $user = User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();
            abort_if(SyncedSpace::whereKey($spaceId)->where('user_id', '!=', $user->id)->exists(), 403);
            $space = $user->syncedSpaces()->firstOrCreate(['id' => $spaceId], ['storage_mode' => 'arca_sync', 'current_key_version' => 1]);
            $keys = $space->wrapped_space_keys_json ?? [];
            foreach ($keys as $key) {
                if ($key['keyGeneration'] === $validated['keyGeneration']) {
                    abort_unless($key == $validated, 409, 'Key generation already exists.');

                    return response()->json(['key' => $key]);
                }
            }
            abort_unless($validated['keyGeneration'] === count($keys) + 1, 409, 'Key generation must be sequential.');
            $keys[] = $validated;
            $space->wrapped_space_keys_json = $keys;
            $space->current_key_version = $validated['keyGeneration'];
            $space->save();

            return response()->json(['key' => $validated]);
        });
    }

    public function registerSpace(Request $request, string $spaceId): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $validated = $request->validate([
            'storage_mode' => 'nullable|string|in:arca_sync,local_only',
            'current_key_version' => 'nullable|integer|in:1',
            'wrapped_space_keys_json' => 'prohibited',
        ]);

        $space = SyncedSpace::firstOrCreate(
            [
                'id' => $spaceId,
                'user_id' => $user->id,
            ],
            [
                'storage_mode' => $validated['storage_mode'] ?? config('arca.default_space_storage_mode', 'arca_sync'),
                'current_key_version' => 1,
            ]
        );

        return response()->json([
            'message' => 'Space registered successfully.',
            'space' => $space,
        ]);
    }

    public function push(Request $request, string $spaceId): JsonResponse
    {
        return DB::transaction(function () use ($request, $spaceId) {
            /** @var User $user */
            $user = User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();

            // Validate device authorization
            $deviceId = $request->header('X-Device-Id') ?? $request->input('device_id');
            if (! $deviceId) {
                return response()->json([
                    'error' => 'DEVICE_ID_REQUIRED',
                    'message' => 'Device ID must be provided via X-Device-Id header or body device_id.',
                ], 400);
            }

            $device = $user->enrolledDevices()
                ->where('id', $deviceId)
                ->whereNull('revoked_at')
                ->first();

            if (! $device) {
                return response()->json([
                    'error' => 'UNAUTHORIZED_DEVICE',
                    'message' => 'Device is not enrolled or has been revoked.',
                ], 403);
            }

            // Check user subscription & quota push policy
            $policy = $user->postExpiryPolicy();
            if (! $policy['canPushRemoteSync']) {
                if ($policy['isOverStorageQuota']) {
                    $errorCode = 'REMOTE_STORAGE_QUOTA_EXCEEDED';
                    $message = 'Remote storage quota exceeded for current tier. Upgrade to Pro or free up space. Note: Local reads, writes, and exports remain 100% available.';
                } elseif ($policy['isOverDeviceLimit']) {
                    $errorCode = 'DEVICE_LIMIT_EXCEEDED_ON_FREE_TIER';
                    $message = 'Enrolled device count exceeds the Free tier limit of 2 devices. Note: Local reads, writes, and exports remain 100% available.';
                } else {
                    $errorCode = 'SUBSCRIPTION_EXPIRED_PUSH_PAUSED';
                    $message = 'Subscription has expired; remote push syncing is paused. Note: Local reads, writes, and exports remain 100% available.';
                }

                return response()->json([
                    'error' => $errorCode,
                    'error_code' => $errorCode,
                    'message' => $message,
                    'canLocalRead' => true,
                    'canLocalWrite' => true,
                    'canLocalExport' => true,
                ], 403);
            }

            $validated = $request->validate([
                'operations' => 'required|array|max:500',
                'operations.*.operation_id' => 'required|uuid',
                'operations.*.entity_id' => 'required|uuid',
                'operations.*.entity_type' => 'required|string|in:schema,record,tombstone',
                'operations.*.base_revision' => 'nullable|integer',
                'operations.*.new_revision' => 'required|integer',
                'operations.*.key_version' => 'required|integer',
                'operations.*.schema_version' => 'required|integer',
                'operations.*.ciphertext_bytes' => 'required|integer|min:0',
                'operations.*.encrypted_envelope' => 'required|array',
            ]);

            // Zero-plaintext enforcement: ensure envelope contains no plaintext leaks
            foreach ($validated['operations'] as $op) {
                $envelope = $op['encrypted_envelope'];
                if ($violation = $this->findPlaintextViolation($envelope)) {
                    return response()->json([
                        'error' => 'ZERO_PLAINTEXT_VIOLATION',
                        'message' => "Encountered forbidden plaintext field [{$violation}] inside encrypted envelope. Server rejects unencrypted client data.",
                    ], 422);
                }
            }

            // Ensure space exists
            $space = SyncedSpace::firstOrCreate(
                ['id' => $spaceId, 'user_id' => $user->id],
                [
                    'storage_mode' => config('arca.default_space_storage_mode', 'arca_sync'),
                    'current_key_version' => 1,
                ]
            );

            abort_if($space->storage_mode === 'local_only', 403, 'Cloud sync is disabled for this space.');
            if ((int) $space->privacy_generation > 0) {
                abort_unless($request->integer('privacy_protocol') === 1 && $request->integer('privacy_generation') === (int) $space->privacy_generation, 409, 'Pull the latest privacy rules with an upgraded client before uploading.');
                foreach ($validated['operations'] as $op) {
                    abort_unless(isset($op['encrypted_envelope']['operation']['collectionId']), 422, 'Collection routing is required after privacy changes.');
                }
            }
            $acknowledgedIds = [];
            $totalNewCiphertextBytes = 0;

            foreach ($validated['operations'] as $op) {
                $opId = $op['operation_id'];

                // Deduplicate idempotently by operation_id
                $existing = SyncOperation::where('operation_id', $opId)->first();
                if ($existing) {
                    abort_unless($existing->user_id === $user->id && strcasecmp($existing->space_id, $spaceId) === 0, 409);
                    $acknowledgedIds[] = $opId;

                    continue;
                }

                $bytes = max((int) $op['ciphertext_bytes'], strlen(json_encode($op['encrypted_envelope'], JSON_THROW_ON_ERROR)));
                abort_if($user->remote_storage_bytes_used + $totalNewCiphertextBytes + $bytes > $user->maxAllowedStorageBytes(), 403, 'Storage quota exceeded.');
                SyncOperation::create([
                    'operation_id' => $opId,
                    'space_id' => $spaceId,
                    'user_id' => $user->id,
                    'device_id' => $deviceId,
                    'entity_id' => $op['entity_id'],
                    'entity_type' => $op['entity_type'],
                    'base_revision' => $op['base_revision'] ?? null,
                    'new_revision' => $op['new_revision'],
                    'key_version' => $op['key_version'],
                    'schema_version' => $op['schema_version'],
                    'ciphertext_bytes' => $bytes,
                    'encrypted_envelope_json' => $op['encrypted_envelope'],
                ]);

                $acknowledgedIds[] = $opId;
                $totalNewCiphertextBytes += $bytes;
            }

            if ($totalNewCiphertextBytes > 0) {
                $space->increment('ciphertext_bytes', $totalNewCiphertextBytes);
                $user->increment('remote_storage_bytes_used', $totalNewCiphertextBytes);
            }

            $device->update(['last_synced_at' => now()]);

            $latestCursor = (int) (SyncOperation::where('space_id', $spaceId)->max('server_cursor') ?? 0);

            return response()->json([
                'space_id' => $spaceId,
                'acknowledged_operation_ids' => $acknowledgedIds,
                'latest_cursor' => $latestCursor,
                'operations_processed' => count($validated['operations']),
                'remote_storage_bytes_used' => (int) $user->remote_storage_bytes_used,
            ]);
        });
    }

    public function pull(Request $request, string $spaceId): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $deviceId = $request->header('X-Device-Id') ?? $request->input('device_id');
        abort_unless($deviceId && $user->enrolledDevices()->whereKey($deviceId)->whereNull('revoked_at')->exists(), 403);
        abort_unless($user->postExpiryPolicy()['canPullRemoteSync'], 403);

        $sinceCursor = max(0, (int) $request->query('since_cursor', 0));
        $limit = max(1, min(500, (int) $request->query('limit', 500)));

        $space = SyncedSpace::where('id', $spaceId)
            ->where('user_id', $user->id)
            ->first();

        $operations = SyncOperation::where('space_id', $spaceId)
            ->where('user_id', $user->id)
            ->where('server_cursor', '>', $sinceCursor)
            ->orderBy('server_cursor', 'asc')
            ->limit($limit + 1)
            ->get();
        $hasMore = $operations->count() > $limit;
        $operations = $operations->take($limit)->values();

        $latestCursor = (int) ($operations->last()?->server_cursor ?? $sinceCursor);

        return response()->json([
            'space_id' => $spaceId,
            'since_cursor' => $sinceCursor,
            'has_more' => $hasMore,
            'latest_cursor' => $latestCursor,
            'operations' => $operations,
            'space_metadata' => $space,
        ]);
    }

    public function privacy(Request $request, string $spaceId): JsonResponse
    {
        $this->authorizeDevice($request);
        $space = $request->user()->syncedSpaces()->whereKey($spaceId)->first();

        return response()->json(['generation' => (int) ($space?->privacy_generation ?? 0), 'rules' => array_values($space?->privacy_rules_json ?? [])]);
    }

    /** Remove only the affected collection's old ciphertext. The encrypted rule contains IDs, never labels. */
    public function updatePrivacy(Request $request, string $spaceId): JsonResponse
    {
        $this->authorizeDevice($request);
        $validated = $request->validate([
            'expected_cursor' => 'required|integer|min:0', 'generation' => 'required|integer|min:0',
            'rule' => 'required|array', 'rule.collectionId' => 'required|uuid', 'rule.changeId' => 'required|uuid',
            'rule.keyGeneration' => 'required|integer|min:1', 'rule.envelope' => 'required|array',
        ]);
        abort_if($this->findPlaintextViolation($validated['rule']) !== null, 422);
        abort_if(strlen(json_encode($validated['rule'], JSON_THROW_ON_ERROR)) > 131072, 413);

        return DB::transaction(function () use ($request, $spaceId, $validated) {
            $user = User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();
            $space = $user->syncedSpaces()->whereKey($spaceId)->lockForUpdate()->first();
            if (! $space) {
                abort_if(SyncedSpace::whereKey($spaceId)->where('user_id', '!=', $user->id)->exists(), 403);
                abort_unless($validated['expected_cursor'] === 0 && $validated['generation'] === 0, 409);
                $space = $user->syncedSpaces()->create(['id' => $spaceId, 'storage_mode' => 'arca_sync', 'current_key_version' => 1]);
            }
            $collectionId = strtolower($validated['rule']['collectionId']);
            $rules = $space->privacy_rules_json ?? [];
            foreach ($rules as $prior) {
                if (strcasecmp($prior['collectionId'], $collectionId) === 0 && strcasecmp($prior['changeId'], $validated['rule']['changeId']) === 0) {
                    return response()->json(['generation' => (int) $space->privacy_generation, 'collection_id' => $collectionId, 'verified' => true]);
                }
            }
            abort_unless((int) $space->privacy_generation === $validated['generation'], 409, 'Privacy policy changed. Pull and retry.');
            $operations = SyncOperation::where('space_id', $spaceId)->where('user_id', $user->id)->get();
            $latest = (int) ($operations->max('server_cursor') ?? 0);
            // A retained client cursor can exceed the current max after an earlier scoped purge.
            abort_if($latest > $validated['expected_cursor'], 409, 'New remote changes must be pulled before privacy deletion.');
            $purge = [];
            foreach ($operations as $op) {
                $routing = $op->encrypted_envelope_json['operation'] ?? [];
                $routedCollection = $routing['collectionId'] ?? null;
                abort_unless(is_string($routedCollection), 409, 'Legacy routing cannot verify a scoped deletion.');
                if (strcasecmp($routedCollection, $collectionId) === 0) {
                    $purge[] = $op;
                }
            }
            // Legacy external objects still require verified object deletion. Inline blobs are transactional.
            abort_if(EncryptedAttachment::where('space_id', $spaceId)->whereNull('encrypted_blob')->exists(), 409, 'Attachment deletion requires verified object removal.');
            $imageQuery = EncryptedAttachment::where('space_id', $spaceId)->where('user_id', $user->id)->where('collection_id', $collectionId);
            $imageBytes = (int) (clone $imageQuery)->sum('byte_size');
            $imageQuery->delete();
            $allEntityIds = $operations->pluck('entity_id')->all();
            // Old snapshots without a classifiable synced record cannot be safely assigned to a collection.
            abort_if(PublicRecordSnapshot::where('space_id', $spaceId)->where('user_id', $user->id)->whereNotIn('record_id', $allEntityIds)->exists(), 409, 'Legacy public snapshots require explicit removal before scoped privacy deletion.');
            $recordIds = array_map(fn ($op) => $op->entity_id, $purge);
            PublicRecordSnapshot::where('space_id', $spaceId)->where('user_id', $user->id)->whereIn('record_id', $recordIds)->delete();
            $bytes = $imageBytes + array_sum(array_map(fn ($op) => (int) $op->ciphertext_bytes, $purge));
            SyncOperation::whereIn('server_cursor', array_map(fn ($op) => $op->server_cursor, $purge))->delete();
            $rules = array_values(array_filter($rules, fn ($rule) => strcasecmp($rule['collectionId'], $collectionId) !== 0));
            $rules[] = $validated['rule'];
            $space->privacy_generation = (int) $space->privacy_generation + 1;
            $space->privacy_rules_json = $rules;
            $space->ciphertext_bytes = max(0, (int) $space->ciphertext_bytes - $bytes);
            $space->save();
            $user->remote_storage_bytes_used = max(0, (int) $user->remote_storage_bytes_used - $bytes);
            $user->save();

            return response()->json(['generation' => (int) $space->privacy_generation, 'collection_id' => $collectionId, 'verified' => true]);
        });
    }

    public function migrateMode(Request $request, string $spaceId): JsonResponse
    {
        return DB::transaction(function () use ($request, $spaceId) {
            /** @var User $user */
            $user = User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();

            $validated = $request->validate([
                'target_mode' => 'required|string|in:arca_sync,local_only',
                'delete_remote_ciphertext' => 'nullable|boolean',
            ]);

            $space = SyncedSpace::where('id', $spaceId)
                ->where('user_id', $user->id)
                ->first();

            if (! $space) {
                return response()->json([
                    'error' => 'NOT_FOUND',
                    'message' => 'Space not found.',
                ], 404);
            }

            if ($validated['target_mode'] === 'local_only') {
                $deleteRemote = $request->boolean('delete_remote_ciphertext', true);

                if ($deleteRemote) {
                    $opBytes = (int) SyncOperation::where('space_id', $spaceId)->sum('ciphertext_bytes');
                    $attBytes = (int) EncryptedAttachment::where('space_id', $spaceId)->sum('byte_size');
                    $freedBytes = $opBytes + $attBytes;

                    $deletedOpCount = SyncOperation::where('space_id', $spaceId)->delete();
                    $deletedAttCount = EncryptedAttachment::where('space_id', $spaceId)->delete();

                    $newStorage = max(0, $user->remote_storage_bytes_used - $freedBytes);
                    $user->update(['remote_storage_bytes_used' => $newStorage]);

                    $space->update([
                        'storage_mode' => 'local_only',
                        'ciphertext_bytes' => 0,
                    ]);

                    $remainingOps = SyncOperation::where('space_id', $spaceId)->count();
                    $remainingAtts = EncryptedAttachment::where('space_id', $spaceId)->count();
                    $verifiedZero = ($remainingOps === 0 && $remainingAtts === 0);
                    $deletedAt = now()->toIso8601String();

                    $signature = hash_hmac(
                        'sha256',
                        "{$spaceId}:{$deletedOpCount}:{$deletedAttCount}:{$deletedAt}",
                        config('app.key') ?: 'arca_secret'
                    );

                    return response()->json([
                        'message' => 'Space migrated to local_only and remote ciphertext permanently deleted.',
                        'receipt' => [
                            'space_id' => $spaceId,
                            'target_mode' => 'local_only',
                            'deleted_operation_count' => $deletedOpCount,
                            'deleted_attachment_count' => $deletedAttCount,
                            'freed_storage_bytes' => $freedBytes,
                            'verified_zero_remaining' => $verifiedZero,
                            'deleted_at' => $deletedAt,
                            'signature_sha256' => $signature,
                        ],
                    ]);
                }

                $space->update(['storage_mode' => 'local_only']);

                return response()->json([
                    'message' => 'Space migrated to local_only mode without deleting remote ciphertext.',
                    'space' => $space,
                ]);
            }

            // Migrate to arca_sync
            $space->update(['storage_mode' => 'arca_sync']);

            return response()->json([
                'message' => 'Space migrated to arca_sync mode.',
                'space' => $space,
            ]);
        });
    }

    private function findPlaintextViolation(array $data): ?string
    {
        foreach ($data as $key => $value) {
            $lowerKey = strtolower((string) $key);
            if (in_array($lowerKey, self::FORBIDDEN_PLAINTEXT_KEYS, true)) {
                return (string) $key;
            }

            if (is_array($value)) {
                $sub = $this->findPlaintextViolation($value);
                if ($sub !== null) {
                    return $sub;
                }
            }
        }

        return null;
    }
}
