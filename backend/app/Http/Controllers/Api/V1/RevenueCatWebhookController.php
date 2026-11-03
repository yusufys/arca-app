<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\RevenueCatWebhookEvent;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class RevenueCatWebhookController extends Controller
{
    public function handle(Request $request): JsonResponse
    {
        $secret = config('arca.revenuecat.webhook_secret');
        $bearer = $request->bearerToken();

        if (! $secret || ! $bearer || ! hash_equals($secret, $bearer)) {
            return response()->json([
                'error' => 'UNAUTHORIZED_WEBHOOK',
                'message' => 'Invalid or missing RevenueCat webhook secret.',
            ], 401);
        }

        $payload = $request->all();
        $event = $payload['event'] ?? $payload;

        $eventId = $event['id'] ?? (string) Str::uuid();
        $eventType = $event['type'] ?? 'UNKNOWN';
        $appUserId = $event['app_user_id'] ?? null;
        $productId = $event['product_id'] ?? null;

        // Idempotency check
        $existing = RevenueCatWebhookEvent::where('event_id', $eventId)->first();
        if ($existing) {
            return response()->json([
                'status' => 'already_processed',
                'event_id' => $eventId,
            ]);
        }

        // Record the event
        RevenueCatWebhookEvent::create([
            'id' => (string) Str::uuid(),
            'event_id' => $eventId,
            'event_type' => $eventType,
            'app_user_id' => (string) $appUserId,
            'product_id' => $productId,
            'payload_json' => $payload,
            'processed_at' => now(),
        ]);

        if (! $appUserId) {
            return response()->json([
                'status' => 'ignored_missing_app_user_id',
                'event_id' => $eventId,
            ]);
        }

        // Find user by revenuecat_app_user_id or uuid
        $user = User::where('revenuecat_app_user_id', $appUserId)
            ->orWhere('uuid', $appUserId)
            ->orWhere('email', $appUserId)
            ->first();

        if ($user) {
            switch ($eventType) {
                case 'INITIAL_PURCHASE':
                case 'RENEWAL':
                case 'UNCANCELLATION':
                case 'PRODUCT_CHANGE':
                    $user->subscription_tier = 'pro';
                    $user->subscription_state = 'active';
                    break;

                case 'BILLING_ISSUE':
                    $user->subscription_tier = 'pro';
                    $user->subscription_state = 'billing_grace_period';
                    break;

                case 'EXPIRATION':
                    $user->subscription_tier = 'free';
                    $user->subscription_state = 'expired';
                    break;

                case 'REFUND':
                    $user->subscription_tier = 'free';
                    $user->subscription_state = 'revoked_or_refunded';
                    break;

                case 'CANCELLATION':
                    $cancelReason = $event['cancel_reason'] ?? null;
                    if ($cancelReason === 'CUSTOMER_SUPPORT') {
                        $user->subscription_tier = 'free';
                        $user->subscription_state = 'revoked_or_refunded';
                    }
                    // For voluntary user cancellations, client retains active Pro access until EXPIRATION event
                    break;
            }

            if ($productId) {
                $user->subscription_product_id = $productId;
            }

            if (! empty($event['expiration_at_ms'])) {
                $user->subscription_expires_at = Carbon::createFromTimestampMs($event['expiration_at_ms']);
            }

            if (empty($user->revenuecat_app_user_id)) {
                $user->revenuecat_app_user_id = $appUserId;
            }

            $user->save();
        }

        return response()->json([
            'status' => 'success',
            'event_id' => $eventId,
            'applied_to_user' => $user?->uuid,
        ]);
    }
}
