<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
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
