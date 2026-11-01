<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\EncryptedAttachment;
use App\Models\SyncedSpace;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AttachmentController extends Controller
{
    public function store(Request $request, string $spaceId): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $validated = $request->validate([
            'id' => 'required|uuid',
            'record_id' => 'required|uuid',
            'byte_size' => 'required|integer|min:1',
            'ciphertext_sha256' => 'required|string',
            'key_version' => 'nullable|integer|min:1',
        ]);

        $byteSize = (int) $validated['byte_size'];

        // Enforce storage quota
        if (($user->remote_storage_bytes_used + $byteSize) > $user->maxAllowedStorageBytes()) {
            return response()->json([
                'error' => 'REMOTE_STORAGE_QUOTA_EXCEEDED',
                'message' => 'Uploading this attachment exceeds your remote ciphertext storage quota. Please upgrade to Pro.',
                'used_bytes' => $user->remote_storage_bytes_used,
                'attempted_bytes' => $byteSize,
                'max_allowed_bytes' => $user->maxAllowedStorageBytes(),
            ], 403);
        }

        $disk = config('arca.attachments_disk', 'r2');
        $objectKey = "spaces/{$spaceId}/records/{$validated['record_id']}/{$validated['id']}.enc";

        $attachment = EncryptedAttachment::updateOrCreate(
            [
                'id' => $validated['id'],
                'user_id' => $user->id,
            ],
            [
                'space_id' => $spaceId,
                'record_id' => $validated['record_id'],
                'byte_size' => $byteSize,
                'ciphertext_sha256' => $validated['ciphertext_sha256'],
                'storage_disk' => $disk,
                'object_key' => $objectKey,
                'key_version' => $validated['key_version'] ?? 1,
            ]
        );

        $user->increment('remote_storage_bytes_used', $byteSize);

        $space = SyncedSpace::where('id', $spaceId)->where('user_id', $user->id)->first();
        if ($space) {
            $space->increment('ciphertext_bytes', $byteSize);
        }

        $presignedUploadUrl = "https://r2.arca.internal/{$objectKey}?expires=" . (time() + 3600);

        return response()->json([
            'message' => 'Attachment metadata registered.',
            'attachment' => $attachment,
            'storage_disk' => $disk,
            'object_key' => $objectKey,
            'upload_url' => $presignedUploadUrl,
        ], 201);
    }

    public function show(Request $request, string $spaceId, string $attachmentId): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $attachment = EncryptedAttachment::where('id', $attachmentId)
            ->where('space_id', $spaceId)
            ->where('user_id', $user->id)
            ->first();

        if (! $attachment) {
            return response()->json([
                'error' => 'NOT_FOUND',
                'message' => 'Encrypted attachment not found.',
            ], 404);
        }

        $presignedDownloadUrl = "https://r2.arca.internal/{$attachment->object_key}?expires=" . (time() + 3600);

        return response()->json([
            'attachment' => $attachment,
            'ciphertext_sha256' => $attachment->ciphertext_sha256,
            'download_url' => $presignedDownloadUrl,
        ]);
    }
}
