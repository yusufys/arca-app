<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\EncryptedAttachment;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class AttachmentController extends Controller
{
    private function authorizeDevice(Request $request): void
    {
        $deviceId = $request->header('X-Device-Id');
        abort_unless($deviceId && $request->user()->enrolledDevices()->whereKey($deviceId)->whereNull('revoked_at')->exists(), 403);
    }

    public function store(Request $request, string $spaceId): JsonResponse
    {
        $this->authorizeDevice($request);
        $rules = [
            'privacy_generation' => 'required|integer|min:0',
            'blob' => 'required|array:attachmentId,spaceId,collectionId,recordId,authorDeviceId,keyGeneration,ciphertextSHA256Hex,encryptedMetadataEnvelope,encryptedDataEnvelope,uploadedAt',
            'blob.attachmentId' => 'required|uuid',
            'blob.spaceId' => 'required|uuid',
            'blob.collectionId' => 'required|uuid',
            'blob.recordId' => 'required|uuid',
            'blob.authorDeviceId' => 'required|string|max:128',
            'blob.keyGeneration' => 'required|integer|min:1',
            'blob.ciphertextSHA256Hex' => 'required|string|size:64|regex:/^[a-fA-F0-9]+$/',
            'blob.uploadedAt' => 'required|date',
        ];
        foreach (['encryptedMetadataEnvelope' => 16384, 'encryptedDataEnvelope' => 6990508] as $field => $limit) {
            $prefix = "blob.{$field}";
            $rules[$prefix] = 'required|array:version,keyId,nonceBase64,ciphertextBase64,tagBase64,aadDescription';
            $rules["{$prefix}.version"] = 'required|integer|in:1';
            $rules["{$prefix}.keyId"] = 'required|uuid';
            $rules["{$prefix}.nonceBase64"] = 'required|string|size:16';
            $rules["{$prefix}.ciphertextBase64"] = "required|string|max:{$limit}";
            $rules["{$prefix}.tagBase64"] = 'required|string|size:24';
            $rules["{$prefix}.aadDescription"] = 'required|string|max:160';
        }
        $validated = $request->validate($rules);
        $blob = $validated['blob'];
        abort_unless(strcasecmp($blob['spaceId'], $spaceId) === 0 && strcasecmp($blob['authorDeviceId'], $request->header('X-Device-Id')) === 0, 422);
        foreach (['encryptedMetadataEnvelope', 'encryptedDataEnvelope'] as $field) {
            $envelope = $blob[$field];
            abort_unless(strlen(base64_decode($envelope['nonceBase64'], true) ?: '') === 12 && strlen(base64_decode($envelope['tagBase64'], true) ?: '') === 16, 422);
            abort_unless(base64_decode($envelope['ciphertextBase64'], true) !== false, 422);
        }
        $data = $blob['encryptedDataEnvelope'];
        abort_if(strlen(base64_decode($data['ciphertextBase64'], true)) > 5 * 1024 * 1024, 413);
        abort_unless(hash_equals(strtolower($blob['ciphertextSHA256Hex']), hash('sha256', $data['ciphertextBase64'].':'.$data['tagBase64'])), 422, 'Ciphertext checksum mismatch.');
        $encoded = json_encode($blob, JSON_THROW_ON_ERROR);
        $bytes = strlen($encoded);
        abort_if($bytes > 7 * 1024 * 1024, 413);

        return DB::transaction(function () use ($request, $spaceId, $validated, $blob, $encoded, $bytes) {
            $user = User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();
            $space = $user->syncedSpaces()->whereKey($spaceId)->lockForUpdate()->firstOrFail();
            abort_unless($space->storage_mode === 'arca_sync', 403);
            abort_unless((int) $space->privacy_generation === $validated['privacy_generation'], 409, 'Pull current privacy rules before uploading images.');
            abort_unless($user->postExpiryPolicy()['canPushRemoteSync'], 403);
            $existing = EncryptedAttachment::where('space_id', $spaceId)->where('user_id', $user->id)->where('reference_id', $blob['attachmentId'])->first();
            if ($existing) {
                abort_unless(strcasecmp($existing->record_id, $blob['recordId']) === 0 && strcasecmp($existing->collection_id, $blob['collectionId']) === 0, 409);
            }
            $delta = $bytes - ($existing?->byte_size ?? 0);
            abort_if($user->remote_storage_bytes_used + $delta > $user->maxAllowedStorageBytes(), 403, 'Image exceeds your cloud storage quota.');
            $attachment = $existing ?? new EncryptedAttachment;
            $attachment->fill([
                'reference_id' => $blob['attachmentId'], 'collection_id' => strtolower($blob['collectionId']),
                'space_id' => $spaceId, 'user_id' => $user->id, 'record_id' => $blob['recordId'],
                'byte_size' => $bytes, 'ciphertext_sha256' => $blob['ciphertextSHA256Hex'],
                'storage_disk' => 'database', 'object_key' => 'inline', 'key_version' => $blob['keyGeneration'],
                'encrypted_blob' => $encoded,
            ])->save();
            $space->increment('ciphertext_bytes', $delta);
            $user->increment('remote_storage_bytes_used', $delta);

            return response()->json(['stored' => true, 'attachment_id' => $blob['attachmentId']], 201);
        });
    }

    public function show(Request $request, string $spaceId, string $attachmentId): JsonResponse
    {
        $this->authorizeDevice($request);
        $request->user()->syncedSpaces()->whereKey($spaceId)->where('storage_mode', 'arca_sync')->firstOrFail();
        $attachment = EncryptedAttachment::where('reference_id', $attachmentId)->where('space_id', $spaceId)
            ->where('user_id', $request->user()->id)->whereNotNull('encrypted_blob')->firstOrFail();

        return response()->json(['blob' => json_decode($attachment->encrypted_blob, true, 512, JSON_THROW_ON_ERROR)])
            ->header('Cache-Control', 'no-store');
    }
}
