<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\RevenueCatWebhookEvent;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

class RevenueCatWebhookController extends Controller
{
    public function handle(Request $request): JsonResponse
    {
        $secret = config('arca.revenuecat.webhook_secret');
        abort_unless($secret && hash_equals($secret, (string) $request->bearerToken()), 401);

        $event = $request->validate([
            'event' => 'required|array',
            'event.id' => 'required|string|max:191',
            'event.type' => 'required|string|max:80',
            'event.environment' => 'nullable|in:SANDBOX,PRODUCTION',
            'event.app_user_id' => 'nullable|string|max:255',
            'event.aliases' => 'nullable|array',
            'event.transferred_from' => 'nullable|array',
            'event.transferred_to' => 'nullable|array',
        ])['event'];
        if ($event['type'] === 'TEST') {
            return response()->json(['status' => 'received']);
        }
        if (($event['environment'] ?? '') !== config('arca.revenuecat.environment')) {
            return response()->json(['status' => 'ignored_environment']);
        }
        $ids = array_unique(array_filter([
            $event['app_user_id'] ?? '', ...($event['aliases'] ?? []),
            ...($event['transferred_from'] ?? []), ...($event['transferred_to'] ?? []),
        ], fn ($id) => is_string($id) && Str::isUuid($id)));

        return DB::transaction(function () use ($ids, $event) {
            // Serialize updates even when older webhook deliveries arrive late. Read current entitlement state.
            $users = User::whereIn('uuid', $ids)->orderBy('id')->lockForUpdate()->get();
            if ($users->isEmpty()) {
                return response()->json(['status' => 'ignored_unknown_account']);
            }
            $receipt = RevenueCatWebhookEvent::firstOrCreate(['event_id' => $event['id']], [
                'event_type' => $event['type'], 'app_user_id' => $users->first()->uuid,
                'payload_json' => ['environment' => $event['environment']], 'processed_at' => now(),
            ]);
            if (! $receipt->wasRecentlyCreated) {
                return response()->json(['status' => 'already_processed']);
            }
            foreach ($users as $user) {
                $this->refresh($user);
            }

            return response()->json(['status' => 'success']);
        });
    }

    private function refresh(User $user): void
    {
        $key = config('arca.revenuecat.server_api_key');
        abort_unless($key, 503, 'RevenueCat server verification is unavailable.');
        $response = Http::acceptJson()->withToken($key)->timeout(8)
            ->get('https://api.revenuecat.com/v1/subscribers/'.$user->uuid);
        abort_unless($response->successful() && is_array($response->json('subscriber.entitlements')), 503, 'Could not verify the current purchase.');
        $subscriber = $response->json('subscriber');
        $entitlement = $subscriber['entitlements'][config('arca.revenuecat.pro_entitlement_id')] ?? null;
        $product = $entitlement['product_identifier'] ?? null;
        $expiry = isset($entitlement['expires_date']) ? Carbon::parse($entitlement['expires_date']) : null;
        $sandbox = config('arca.revenuecat.environment') === 'SANDBOX';
        $subscription = $subscriber['subscriptions'][$product] ?? [];
        $grace = isset($subscription['grace_period_expires_date']) ? Carbon::parse($subscription['grace_period_expires_date']) : null;
        $active = false;
        if ($product === 'lifetime') {
            foreach ($subscriber['non_subscriptions'][$product] ?? [] as $purchase) {
                if (($purchase['is_sandbox'] ?? null) === $sandbox && empty($purchase['refunded_at'])) {
                    $active = true;
                    break;
                }
            }
        } elseif (in_array($product, ['monthly', 'yearly'], true)) {
            $active = ($subscription['is_sandbox'] ?? null) === $sandbox && empty($subscription['refunded_at'])
                && ($expiry?->isFuture() || $grace?->isFuture());
        }
        $wasPaid = $user->subscription_tier === 'pro' || $user->subscription_state === 'expired';
        $user->subscription_state = $active
            ? (empty($subscription['billing_issues_detected_at']) ? 'active' : 'billing_grace_period')
            : ($wasPaid ? 'expired' : 'active');
        $user->subscription_tier = $active ? 'pro' : 'free';
        $user->subscription_product_id = $active ? $product : null;
        $user->subscription_expires_at = $active ? ($grace && $expiry && $grace->greaterThan($expiry) ? $grace : $expiry) : null;
        $user->revenuecat_app_user_id = $user->uuid;
        $user->save();
    }
}
