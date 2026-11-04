<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\PublicRecordSnapshot;
use App\Models\SyncedSpace;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class PublicSnapshotController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $validated = $request->validate([
            'space_id' => 'required|uuid',
            'record_id' => 'required|uuid',
            'selected_fields' => 'required|array',
            'expires_at' => 'nullable|date',
        ]);

        return DB::transaction(function () use ($user, $validated) {
            User::whereKey($user->id)->lockForUpdate()->firstOrFail();
            // Snapshot fields are plaintext. Encrypted privacy rules cannot be checked by this endpoint.
            // Keep this independent outgoing path closed for any Space using sensitive data controls.
            abort_if(SyncedSpace::whereKey($validated['space_id'])->where('user_id', $user->id)->where('privacy_generation', '>', 0)->exists(), 409, 'Public snapshots are unavailable for Spaces with sensitive data controls.');
            $shareToken = Str::random(32);

            $snapshot = PublicRecordSnapshot::create([
                'user_id' => $user->id,
                'space_id' => $validated['space_id'],
                'record_id' => $validated['record_id'],
                'share_token' => $shareToken,
                'selected_fields_json' => $validated['selected_fields'],
                'expires_at' => $validated['expires_at'] ?? null,
            ]);

            $shareUrl = url("/api/v1/snapshots/{$shareToken}");

            return response()->json([
                'message' => 'Public snapshot created successfully.',
                'share_token' => $shareToken,
                'share_url' => $shareUrl,
                'snapshot' => $snapshot,
            ], 201);
        });
    }

    public function show(string $shareToken): JsonResponse
    {
        $snapshot = PublicRecordSnapshot::where('share_token', $shareToken)->first();

        if (! $snapshot) {
            return response()->json([
                'error' => 'NOT_FOUND',
                'message' => 'Snapshot not found.',
            ], 404);
        }

        // Check if revoked or expired
        $isRevoked = $snapshot->revoked_at !== null;
        $isExpired = $snapshot->expires_at !== null && $snapshot->expires_at->isPast();

        if ($isRevoked || $isExpired) {
            return response()->json([
                'error' => 'SNAPSHOT_REVOKED_OR_EXPIRED',
                'message' => 'This shared record snapshot has been revoked or expired.',
                'revoked' => $isRevoked,
                'expired' => $isExpired,
            ], 410);
        }

        return response()->json([
            'space_id' => $snapshot->space_id,
            'record_id' => $snapshot->record_id,
            'selected_fields' => $snapshot->selected_fields_json,
            'created_at' => $snapshot->created_at,
            'expires_at' => $snapshot->expires_at,
        ]);
    }

    public function revoke(Request $request, string $shareToken): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $snapshot = PublicRecordSnapshot::where('share_token', $shareToken)
            ->where('user_id', $user->id)
            ->first();

        if (! $snapshot) {
            return response()->json([
                'error' => 'NOT_FOUND',
                'message' => 'Snapshot not found or unauthorized.',
            ], 404);
        }

        $snapshot->update(['revoked_at' => now()]);

        return response()->json([
            'message' => 'Snapshot successfully revoked.',
            'share_token' => $shareToken,
            'revoked_at' => $snapshot->revoked_at,
        ]);
    }
}
