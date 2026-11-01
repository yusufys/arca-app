<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppAnnouncement;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AppFeedController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $platform = $request->query('platform'); // 'ios' | 'android'
        $tier = $request->query('tier'); // 'free' | 'pro'

        $query = AppAnnouncement::where('is_active', true);

        if ($platform) {
            $query->whereIn('target_platform', ['all', $platform]);
        }

        if ($tier) {
            $query->whereIn('target_tier', ['all', $tier]);
        }

        $now = now();
        $query->where(function ($q) use ($now) {
            $q->whereNull('starts_at')->orWhere('starts_at', '<=', $now);
        })->where(function ($q) use ($now) {
            $q->whereNull('ends_at')->orWhere('ends_at', '>=', $now);
        });

        $announcements = $query->orderBy('priority', 'desc')
            ->orderBy('created_at', 'desc')
            ->get();

        return response()->json([
            'announcements' => $announcements,
            'remote_config' => [
                'default_space_storage_mode' => config('arca.default_space_storage_mode', 'arca_sync'),
                'local_only_available' => (bool) config('arca.local_only_available', true),
                'sensitive_medical_default_mode' => config('arca.sensitive_medical_default_mode', 'local_only'),
                'remote_retention_days' => (int) config('arca.remote_retention_days', 90),
                'quotas' => config('arca.quotas'),
            ],
        ]);
    }
}
