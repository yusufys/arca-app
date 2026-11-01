<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\EnrolledDevice;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class DeviceController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $devices = $user->enrolledDevices()
            ->orderBy('created_at', 'desc')
            ->get();

        return response()->json([
            'devices' => $devices,
            'active_count' => $user->activeEnrolledDevicesCount(),
            'max_allowed' => $user->maxAllowedDevices(),
        ]);
    }

    public function enroll(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $validated = $request->validate([
            'id' => 'nullable|uuid',
            'device_name' => 'required|string|max:255',
            'platform' => 'required|string|in:ios,android,macos',
            'public_key_x25519' => 'required|string',
        ]);

        $deviceId = $validated['id'] ?? (string) Str::uuid();

        $existingDevice = $user->enrolledDevices()->where('id', $deviceId)->first();

        if ($existingDevice) {
            $existingDevice->update([
                'device_name' => $validated['device_name'],
                'platform' => $validated['platform'],
                'public_key_x25519' => $validated['public_key_x25519'],
                'revoked_at' => null,
                'last_synced_at' => now(),
            ]);

            return response()->json([
                'message' => 'Device updated successfully.',
                'device' => $existingDevice,
            ]);
        }

        if ($user->activeEnrolledDevicesCount() >= $user->maxAllowedDevices()) {
            return response()->json([
                'error' => 'DEVICE_LIMIT_EXCEEDED',
                'error_code' => 'DEVICE_LIMIT_EXCEEDED',
                'message' => "Device limit exceeded for current subscription tier ({$user->subscription_tier}). Maximum allowed devices: {$user->maxAllowedDevices()}.",
                'max_allowed_devices' => $user->maxAllowedDevices(),
                'active_devices_count' => $user->activeEnrolledDevicesCount(),
            ], 403);
        }

        $device = $user->enrolledDevices()->create([
            'id' => $deviceId,
            'device_name' => $validated['device_name'],
            'platform' => $validated['platform'],
            'public_key_x25519' => $validated['public_key_x25519'],
            'last_synced_at' => now(),
        ]);

        return response()->json([
            'message' => 'Device enrolled successfully.',
            'device' => $device,
        ], 201);
    }

    public function revoke(Request $request, string $deviceId): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $device = $user->enrolledDevices()->where('id', $deviceId)->first();

        if (! $device) {
            return response()->json([
                'error' => 'NOT_FOUND',
                'message' => 'Device not found.',
            ], 404);
        }

        $device->update([
            'revoked_at' => now(),
        ]);

        // Increment current_key_version on all arca_sync spaces belonging to the user
        $user->syncedSpaces()
            ->where('storage_mode', 'arca_sync')
            ->increment('current_key_version');

        return response()->json([
            'message' => 'Device revoked successfully and space key versions rotated.',
            'device' => $device,
        ]);
    }
}
