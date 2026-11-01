<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\EnrolledDevice;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|max:255|unique:users,email',
            'password' => 'required|string|min:8',
            'device_id' => 'nullable|uuid',
            'device_token' => 'nullable|string|max:191',
            'device_name' => 'nullable|string|max:255',
            'platform' => 'nullable|string|in:ios,android,macos',
            'public_key_x25519' => 'nullable|string',
        ]);

        $user = User::create([
            'name' => $validated['name'],
            'email' => $validated['email'],
            'password' => Hash::make($validated['password']),
            'api_token' => Str::random(60),
            'subscription_tier' => 'free',
            'subscription_state' => 'active',
            'remote_storage_bytes_used' => 0,
        ]);

        $associatedDevice = $this->associateDeviceWithUser($user, $validated);

        return response()->json([
            'user' => [
                'id' => $user->id,
                'uuid' => $user->uuid,
                'name' => $user->name,
                'email' => $user->email,
                'subscription_tier' => $user->subscription_tier,
                'subscription_state' => $user->subscription_state,
                'remote_storage_bytes_used' => $user->remote_storage_bytes_used,
                'created_at' => $user->created_at,
            ],
            'api_token' => $user->api_token,
            'associated_device' => $associatedDevice,
            'default_space_storage_mode' => config('arca.default_space_storage_mode', 'arca_sync'),
            'entitlements' => [
                'tier' => $user->subscription_tier,
                'max_devices' => $user->maxAllowedDevices(),
                'max_storage_bytes' => $user->maxAllowedStorageBytes(),
                'active_devices' => $user->activeEnrolledDevicesCount(),
            ],
            'post_expiry_policy' => $user->postExpiryPolicy(),
        ], 201);
    }

    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => 'required|email',
            'password' => 'required|string',
            'device_id' => 'nullable|uuid',
            'device_token' => 'nullable|string|max:191',
            'device_name' => 'nullable|string|max:255',
            'platform' => 'nullable|string|in:ios,android,macos',
            'public_key_x25519' => 'nullable|string',
        ]);

        $user = User::where('email', $validated['email'])->first();

        if (! $user || ! Hash::check($validated['password'], $user->password)) {
            return response()->json([
                'error' => 'INVALID_CREDENTIALS',
                'message' => 'The provided email or password is incorrect.',
            ], 401);
        }

        if (empty($user->api_token)) {
            $user->api_token = Str::random(60);
            $user->save();
        }

        $associatedDevice = $this->associateDeviceWithUser($user, $validated);

        return response()->json([
            'user' => [
                'id' => $user->id,
                'uuid' => $user->uuid,
                'name' => $user->name,
                'email' => $user->email,
                'subscription_tier' => $user->subscription_tier,
                'subscription_state' => $user->subscription_state,
                'remote_storage_bytes_used' => $user->remote_storage_bytes_used,
                'created_at' => $user->created_at,
            ],
            'api_token' => $user->api_token,
            'associated_device' => $associatedDevice,
            'default_space_storage_mode' => config('arca.default_space_storage_mode', 'arca_sync'),
            'entitlements' => [
                'tier' => $user->subscription_tier,
                'max_devices' => $user->maxAllowedDevices(),
                'max_storage_bytes' => $user->maxAllowedStorageBytes(),
                'active_devices' => $user->activeEnrolledDevicesCount(),
            ],
            'post_expiry_policy' => $user->postExpiryPolicy(),
        ]);
    }

    public function associateDeviceWithUser(User $user, array $data): ?EnrolledDevice
    {
        $deviceId = $data['device_id'] ?? null;
        $deviceToken = $data['device_token'] ?? null;

        if (! $deviceId && ! $deviceToken) {
            return null;
        }

        $device = null;
        if ($deviceId) {
            $device = EnrolledDevice::where('id', $deviceId)->first();
        }
        if (! $device && $deviceToken) {
            $device = EnrolledDevice::where('device_token', $deviceToken)->first();
        }

        $deviceName = $data['device_name'] ?? ($device?->device_name ?? 'Arca Client');
        $platform = $data['platform'] ?? ($device?->platform ?? 'ios');
        $publicKey = $data['public_key_x25519'] ?? ($device?->public_key_x25519 ?? null);

        if ($device) {
            if ($device->user_id === $user->id) {
                if ($deviceToken) {
                    EnrolledDevice::where('device_token', $deviceToken)->where('id', '!=', $device->id)->update(['device_token' => null]);
                    $device->device_token = $deviceToken;
                }
                if (! empty($data['device_name'])) {
                    $device->device_name = $data['device_name'];
                }
                if (! empty($data['platform'])) {
                    $device->platform = $data['platform'];
                }
                if (! empty($data['public_key_x25519'])) {
                    $device->public_key_x25519 = $data['public_key_x25519'];
                }
                $device->revoked_at = null;
                $device->last_synced_at = now();
                $device->save();
                $device->refresh();

                return $device;
            }

            if ($user->activeEnrolledDevicesCount() < $user->maxAllowedDevices()) {
                if ($deviceToken) {
                    EnrolledDevice::where('device_token', $deviceToken)->where('id', '!=', $device->id)->update(['device_token' => null]);
                    $device->device_token = $deviceToken;
                }
                $device->user_id = $user->id;
                if (! empty($data['device_name'])) {
                    $device->device_name = $data['device_name'];
                }
                if (! empty($data['platform'])) {
                    $device->platform = $data['platform'];
                }
                if (! empty($data['public_key_x25519'])) {
                    $device->public_key_x25519 = $data['public_key_x25519'];
                }
                $device->revoked_at = null;
                $device->last_synced_at = now();
                $device->save();
                $device->refresh();

                return $device;
            }

            return null;
        }

        if ($user->activeEnrolledDevicesCount() < $user->maxAllowedDevices()) {
            if ($deviceToken) {
                EnrolledDevice::where('device_token', $deviceToken)->update(['device_token' => null]);
            }

            $device = EnrolledDevice::create([
                'id' => $deviceId ?: (string) Str::uuid(),
                'user_id' => $user->id,
                'device_token' => $deviceToken,
                'device_name' => $deviceName,
                'platform' => $platform,
                'public_key_x25519' => $publicKey,
                'last_synced_at' => now(),
                'revoked_at' => null,
            ]);

            return $device;
        }

        return null;
    }

    public function me(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        return response()->json([
            'user' => [
                'id' => $user->id,
                'uuid' => $user->uuid,
                'name' => $user->name,
                'email' => $user->email,
                'subscription_tier' => $user->subscription_tier,
                'subscription_state' => $user->subscription_state,
                'subscription_expires_at' => $user->subscription_expires_at,
                'remote_storage_bytes_used' => $user->remote_storage_bytes_used,
                'is_admin' => $user->is_admin,
                'created_at' => $user->created_at,
            ],
            'default_space_storage_mode' => config('arca.default_space_storage_mode', 'arca_sync'),
            'quotas' => config('arca.quotas'),
            'entitlements' => [
                'tier' => $user->subscription_tier,
                'subscription_state' => $user->subscription_state,
                'max_devices' => $user->maxAllowedDevices(),
                'max_storage_bytes' => $user->maxAllowedStorageBytes(),
                'active_devices' => $user->activeEnrolledDevicesCount(),
            ],
            'post_expiry_policy' => $user->postExpiryPolicy(),
        ]);
    }
}
