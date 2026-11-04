<?php

namespace App\Http\Middleware;

use App\Models\ApiSession;
use App\Models\User;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class ArcaApiTokenAuth
{
    public function handle(Request $request, Closure $next): Response
    {
        $token = $request->bearerToken();
        $session = $token ? ApiSession::find(hash('sha256', $token)) : null;
        abort_unless($session, 401, 'Sign in again.');
        $user = User::findOrFail($session->user_id);
        if ($session->device_id === null) {
            abort_if($session->created_at->lt(now()->subMinutes(15)), 401, 'Sign in again.');
            $bootstrapRoutes = ['GET api/v1/auth/me', 'GET api/v1/sync/recovery', 'POST api/v1/devices/enroll', 'DELETE api/v1/account'];
            abort_unless(in_array($request->method().' '.$request->path(), $bootstrapRoutes, true), 403);
        } else {
            abort_unless($user->enrolledDevices()->whereKey($session->device_id)->whereNull('revoked_at')->exists(), 403);
            foreach ([$request->header('X-Device-Id'), $request->input('device_id')] as $claim) {
                abort_if($claim !== null && (! is_string($claim) || strcasecmp($claim, $session->device_id) !== 0), 403);
            }
            $request->headers->set('X-Device-Id', $session->device_id);
        }

        $request->attributes->set('arca_session', $session);
        auth()->setUser($user);
        $request->setUserResolver(fn () => $user);

        return $next($request);
    }
}
