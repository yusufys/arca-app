<?php

namespace Tests\Feature;

use App\Models\ApiSession;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\TestCase;

class ReleaseAccessTest extends TestCase
{
    use RefreshDatabase;

    public function test_revoked_session_cannot_impersonate_or_reenroll_as_an_active_device(): void
    {
        $user = User::factory()->create();
        $phone = $user->enrolledDevices()->create(['device_name' => 'Phone', 'platform' => 'ios']);
        $other = $user->enrolledDevices()->create(['device_name' => 'Other', 'platform' => 'ios']);
        $token = ApiSession::issue($user, $phone->id);
        $this->withToken($token)->withHeader('X-Device-Id', $other->id)->getJson('/api/v1/spaces')->assertForbidden();
        $phone->update(['revoked_at' => now()]);
        $this->getJson('/api/v1/spaces')->assertForbidden();
        $this->postJson('/api/v1/devices/enroll', ['id' => $other->id])->assertForbidden();
        $this->getJson('/api/v1/sync/recovery')->assertForbidden();
        $this->withToken($user->api_token)->getJson('/api/v1/auth/me')->assertUnauthorized();
        $this->withToken(ApiSession::issue($user, $other->id))->getJson('/api/v1/spaces')->assertOk();
    }

    public function test_lifetime_entitlement_is_reconciled_once_and_sandbox_does_not_grant_production_quota(): void
    {
        $user = User::factory()->create();
        config(['arca.revenuecat.webhook_secret' => 'hook', 'arca.revenuecat.server_api_key' => 'server',
            'arca.revenuecat.environment' => 'PRODUCTION', 'arca.revenuecat.pro_entitlement_id' => 'arca_app_pro']);
        $subscriber = ['entitlements' => ['arca_app_pro' => ['product_identifier' => 'lifetime', 'expires_date' => null]],
            'non_subscriptions' => ['lifetime' => [['is_sandbox' => false]]]];
        Http::fakeSequence()->pushStatus(503)->push(['subscriber' => $subscriber]);
        $event = ['id' => (string) Str::uuid(), 'type' => 'NON_RENEWING_PURCHASE', 'app_user_id' => $user->uuid, 'environment' => 'SANDBOX'];
        $this->withToken('hook')->postJson('/api/v1/webhooks/revenuecat', ['event' => $event])->assertOk();
        $this->assertSame('free', $user->fresh()->subscription_tier);
        $event['environment'] = 'PRODUCTION';
        $this->postJson('/api/v1/webhooks/revenuecat', ['event' => $event])->assertServiceUnavailable();
        $this->postJson('/api/v1/webhooks/revenuecat', ['event' => $event])->assertOk();
        $this->postJson('/api/v1/webhooks/revenuecat', ['event' => $event])->assertJsonPath('status', 'already_processed');
        $this->assertSame('pro', $user->fresh()->subscription_tier);
        $this->assertNull($user->fresh()->subscription_expires_at);
        Http::assertSentCount(2);
    }
}
