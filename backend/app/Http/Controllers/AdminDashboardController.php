<?php

namespace App\Http\Controllers;

use App\Models\AppAnnouncement;
use App\Models\EncryptedAttachment;
use App\Models\EnrolledDevice;
use App\Models\PublicRecordSnapshot;
use App\Models\SyncedSpace;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class AdminDashboardController extends Controller
{
    public function index(Request $request): View|JsonResponse
    {
        $totalUsers = User::count();
        $proSubscribers = User::where('subscription_tier', 'pro')->count();
        $enrolledDevices = EnrolledDevice::count();
        $activeDevices = EnrolledDevice::whereNull('revoked_at')->count();
        $guestDevices = EnrolledDevice::whereNull('user_id')->count();
        $userLinkedDevices = EnrolledDevice::whereNotNull('user_id')->count();
        $syncedSpaces = SyncedSpace::count();

        $spaceCiphertextBytes = (int) SyncedSpace::sum('ciphertext_bytes');
        $attachmentBytes = (int) EncryptedAttachment::sum('byte_size');
        $totalCiphertextBytes = $spaceCiphertextBytes + $attachmentBytes;

        $activeAnnouncements = AppAnnouncement::where('is_active', true)->count();
        $publicSnapshots = PublicRecordSnapshot::count();

        $stats = [
            'total_users' => $totalUsers,
            'pro_subscribers' => $proSubscribers,
            'enrolled_devices' => $enrolledDevices,
            'active_devices' => $activeDevices,
            'guest_devices' => $guestDevices,
            'user_linked_devices' => $userLinkedDevices,
            'synced_spaces' => $syncedSpaces,
            'ciphertext_bytes' => $totalCiphertextBytes,
            'formatted_ciphertext_bytes' => $this->formatBytes($totalCiphertextBytes),
            'active_announcements' => $activeAnnouncements,
            'public_snapshots' => $publicSnapshots,
            'zero_knowledge_e2ee' => true,
        ];

        $announcements = AppAnnouncement::orderBy('priority', 'desc')
            ->orderBy('created_at', 'desc')
            ->get();

        $recentDevices = EnrolledDevice::with('user')
            ->orderBy('last_synced_at', 'desc')
            ->orderBy('created_at', 'desc')
            ->limit(10)
            ->get();

        if ($request->expectsJson()) {
            return response()->json([
                'stats' => $stats,
                'announcements' => $announcements,
                'recent_devices' => $recentDevices,
            ]);
        }

        return view('admin.dashboard', [
            'stats' => $stats,
            'announcements' => $announcements,
            'recent_devices' => $recentDevices,
            'recentDevices' => $recentDevices,
        ]);
    }

    public function storeAnnouncement(Request $request): RedirectResponse|JsonResponse
    {
        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'body' => 'required|string',
            'cta_label' => 'nullable|string|max:100',
            'cta_url' => 'nullable|url|max:255',
            'placement' => 'nullable|string|in:home_banner,settings_card,announcement_modal',
            'target_platform' => 'nullable|string|in:all,ios,android',
            'target_tier' => 'nullable|string|in:all,free,pro',
            'priority' => 'nullable|integer',
            'is_active' => 'nullable|boolean',
        ]);

        $announcement = AppAnnouncement::create([
            'title' => $validated['title'],
            'body' => $validated['body'],
            'cta_label' => $validated['cta_label'] ?? null,
            'cta_url' => $validated['cta_url'] ?? null,
            'placement' => $validated['placement'] ?? 'home_banner',
            'target_platform' => $validated['target_platform'] ?? 'all',
            'target_tier' => $validated['target_tier'] ?? 'all',
            'priority' => $validated['priority'] ?? 0,
            'is_active' => $request->has('is_active') ? $request->boolean('is_active') : true,
        ]);

        if ($request->expectsJson()) {
            return response()->json([
                'message' => 'Announcement created successfully.',
                'announcement' => $announcement,
            ], 201);
        }

        return redirect('/admin')->with('status', 'Announcement published successfully.');
    }

    public function toggleAnnouncement(Request $request, string $id): RedirectResponse|JsonResponse
    {
        $announcement = AppAnnouncement::findOrFail($id);
        $announcement->update([
            'is_active' => ! $announcement->is_active,
        ]);

        if ($request->expectsJson()) {
            return response()->json([
                'message' => 'Announcement status toggled.',
                'announcement' => $announcement,
            ]);
        }

        return redirect('/admin')->with('status', "Announcement \"{$announcement->title}\" status updated.");
    }

    public function downloadApk()
    {
        $apkPath = base_path('../Arca-debug.apk');
        if (! file_exists($apkPath)) {
            $apkPath = base_path('../android/app/build/outputs/apk/debug/app-debug.apk');
        }

        abort_unless(file_exists($apkPath), 404, 'Arca-debug.apk not found. Run ./test-devices.sh to build it.');

        return response()->download($apkPath, 'Arca-debug.apk', [
            'Content-Type' => 'application/vnd.android.package-archive',
            'Cache-Control' => 'no-store, no-cache, must-revalidate',
        ]);
    }

    private function formatBytes(int $bytes): string
    {
        if ($bytes <= 0) {
            return '0 B';
        }

        $units = ['B', 'KB', 'MB', 'GB', 'TB'];
        $power = min((int) floor(log($bytes, 1024)), count($units) - 1);

        return round($bytes / pow(1024, $power), 2) . ' ' . $units[$power];
    }
}
