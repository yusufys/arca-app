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

    public function registerDevice(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'id' => 'nullable|uuid',
            'device_id' => 'nullable|uuid',
            'device_token' => 'required|string|max:191',
            'device_name' => 'required|string|max:255',
            'platform' => 'required|string|in:ios,android,macos',
            'app_version' => 'nullable|string|max:64',
            'public_key_x25519' => 'nullable|string',
        ]);

        $deviceId = $validated['id'] ?? $validated['device_id'] ?? null;
        $deviceToken = $validated['device_token'];

        /** @var User|null $authenticatedUser */
        $authenticatedUser = null;
        if ($bearerToken = $request->bearerToken()) {
            $authenticatedUser = User::where('api_token', $bearerToken)->first();
        }

        $device = null;
        if ($deviceId) {
            $device = EnrolledDevice::where('id', $deviceId)->first();
        }
        if (! $device && $deviceToken) {
            $device = EnrolledDevice::where('device_token', $deviceToken)->first();
        }

        if ($device) {
            EnrolledDevice::where('device_token', $deviceToken)
                ->where('id', '!=', $device->id)
                ->update(['device_token' => null]);

            $device->device_token = $deviceToken;
            $device->device_name = $validated['device_name'];
            $device->platform = $validated['platform'];
            if (! empty($validated['app_version'])) {
                $device->app_version = $validated['app_version'];
            }
            if (array_key_exists('public_key_x25519', $validated) && $validated['public_key_x25519'] !== null) {
                $device->public_key_x25519 = $validated['public_key_x25519'];
            }
            $device->last_synced_at = now();

            if ($authenticatedUser && $device->user_id === null) {
                if ($authenticatedUser->activeEnrolledDevicesCount() < $authenticatedUser->maxAllowedDevices()) {
                    $device->user_id = $authenticatedUser->id;
                    $device->revoked_at = null;
                }
            }

            $device->save();
            $device->refresh();

            return response()->json([
                'message' => 'Device registration updated successfully.',
                'device' => $device,
            ], 200);
        }

        $userId = null;
        if ($authenticatedUser && $authenticatedUser->activeEnrolledDevicesCount() < $authenticatedUser->maxAllowedDevices()) {
            $userId = $authenticatedUser->id;
        }

        EnrolledDevice::where('device_token', $deviceToken)->update(['device_token' => null]);

        $device = EnrolledDevice::create([
            'id' => $deviceId ?: (string) Str::uuid(),
            'user_id' => $userId,
            'device_token' => $deviceToken,
            'device_name' => $validated['device_name'],
            'platform' => $validated['platform'],
            'app_version' => $validated['app_version'] ?? '1.0.0',
            'public_key_x25519' => $validated['public_key_x25519'] ?? null,
            'last_synced_at' => now(),
        ]);

        return response()->json([
            'message' => 'Device registered successfully.',
            'device' => $device,
        ], 201);
    }

    public function enroll(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $validated = $request->validate([
            'id' => 'nullable|uuid',
            'device_id' => 'nullable|uuid',
            'device_token' => 'nullable|string|max:191',
            'device_name' => 'required|string|max:255',
            'platform' => 'required|string|in:ios,android,macos',
            'app_version' => 'nullable|string|max:64',
            'public_key_x25519' => 'required|string',
        ]);

        $deviceId = $validated['id'] ?? $validated['device_id'] ?? (string) Str::uuid();
        $deviceToken = $validated['device_token'] ?? null;

        // 1. Check if device already enrolled by this user
        $existingDevice = $user->enrolledDevices()->where('id', $deviceId)->first();
        if (! $existingDevice && $deviceToken) {
            $existingDevice = $user->enrolledDevices()->where('device_token', $deviceToken)->first();
        }

        if ($existingDevice) {
            if ($deviceToken) {
                EnrolledDevice::where('device_token', $deviceToken)
                    ->where('id', '!=', $existingDevice->id)
                    ->update(['device_token' => null]);
                $existingDevice->device_token = $deviceToken;
            }
            $existingDevice->device_name = $validated['device_name'];
            $existingDevice->platform = $validated['platform'];
            if (! empty($validated['app_version'])) {
                $existingDevice->app_version = $validated['app_version'];
            }
            $existingDevice->public_key_x25519 = $validated['public_key_x25519'];
            $existingDevice->revoked_at = null;
            $existingDevice->last_synced_at = now();
            $existingDevice->save();
            $existingDevice->refresh();

            return response()->json([
                'message' => 'Device updated successfully.',
                'device' => $existingDevice,
            ]);
        }

        // 2. Check device limit before creating or claiming an anonymous device
        if ($user->activeEnrolledDevicesCount() >= $user->maxAllowedDevices()) {
            return response()->json([
                'error' => 'DEVICE_LIMIT_EXCEEDED',
                'error_code' => 'DEVICE_LIMIT_EXCEEDED',
                'message' => "Device limit exceeded for current subscription tier ({$user->subscription_tier}). Maximum allowed devices: {$user->maxAllowedDevices()}.",
                'max_allowed_devices' => $user->maxAllowedDevices(),
                'active_devices_count' => $user->activeEnrolledDevicesCount(),
            ], 403);
        }

        // 3. Check if a device with this id or device_token was previously registered anonymously
        $preExistingDevice = EnrolledDevice::where('id', $deviceId)->first();
        if (! $preExistingDevice && $deviceToken) {
            $preExistingDevice = EnrolledDevice::where('device_token', $deviceToken)->first();
        }

        if ($preExistingDevice) {
            if ($deviceToken) {
                EnrolledDevice::where('device_token', $deviceToken)
                    ->where('id', '!=', $preExistingDevice->id)
                    ->update(['device_token' => null]);
                $preExistingDevice->device_token = $deviceToken;
            }
            $preExistingDevice->user_id = $user->id;
            $preExistingDevice->device_name = $validated['device_name'];
            $preExistingDevice->platform = $validated['platform'];
            if (! empty($validated['app_version'])) {
                $preExistingDevice->app_version = $validated['app_version'];
            }
            $preExistingDevice->public_key_x25519 = $validated['public_key_x25519'];
            $preExistingDevice->revoked_at = null;
            $preExistingDevice->last_synced_at = now();
            $preExistingDevice->save();
            $preExistingDevice->refresh();

            return response()->json([
                'message' => 'Device enrolled successfully.',
                'device' => $preExistingDevice,
            ], 201);
        }

        if ($deviceToken) {
            EnrolledDevice::where('device_token', $deviceToken)->update(['device_token' => null]);
        }

        $device = $user->enrolledDevices()->create([
            'id' => $deviceId,
            'device_token' => $deviceToken,
            'device_name' => $validated['device_name'],
            'platform' => $validated['platform'],
            'app_version' => $validated['app_version'] ?? '1.0.0',
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
