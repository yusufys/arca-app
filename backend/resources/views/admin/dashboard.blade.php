<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Arca Admin Dashboard</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = {
            theme: {
                extend: {
                    colors: {
                        arca: {
                            50: '#eef2ff',
                            100: '#e0e7ff',
                            500: '#6366f1',
                            600: '#4f46e5',
                            700: '#4338ca',
                            900: '#1e1b4b',
                        }
                    }
                }
            }
        }
    </script>
</head>
<body class="bg-slate-900 text-slate-100 min-h-screen">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Header -->
        <div class="flex flex-col md:flex-row md:items-center md:justify-between pb-6 border-b border-slate-800 gap-4">
            <div>
                <div class="flex items-center gap-3">
                    <div class="w-10 h-10 rounded-xl bg-indigo-600 flex items-center justify-center font-bold text-xl shadow-lg shadow-indigo-500/30">
                        A
                    </div>
                    <div>
                        <h1 class="text-2xl font-bold tracking-tight text-white">Arca System Administration</h1>
                        <p class="text-sm text-slate-400">Zero-Knowledge Encrypted Monorepo Cloud Backend</p>
                    </div>
                </div>
            </div>

            <!-- E2EE Zero-Knowledge Status Badge -->
            <div class="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-emerald-950/60 border border-emerald-500/30 text-emerald-300 text-xs font-semibold shadow-sm">
                <span class="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse"></span>
                <span>E2EE Zero-Knowledge Verified (Server holds ZERO plaintext keys or decrypted data)</span>
            </div>
        </div>

        @if (session('status'))
            <div class="mt-6 p-4 rounded-xl bg-emerald-900/40 border border-emerald-500/40 text-emerald-200 text-sm flex items-center justify-between">
                <span>{{ session('status') }}</span>
            </div>
        @endif

        <!-- Wireless OTA APK Download & QR Code Banner -->
        <div class="mt-6 p-6 rounded-2xl bg-gradient-to-r from-indigo-950/80 via-slate-800/80 to-slate-800/80 border border-indigo-500/30 shadow-xl flex flex-col md:flex-row items-center justify-between gap-6">
            <div class="space-y-2">
                <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-indigo-500/20 text-indigo-300 text-xs font-semibold">
                    <span>📱 Wireless Device Testing (Over Local Wi-Fi)</span>
                </div>
                <h2 class="text-xl font-bold text-white">Install Latest Android APK Without Cables</h2>
                <p class="text-sm text-slate-300 max-w-2xl">
                    Scan the QR code with your Android phone camera (connected to the same Wi-Fi) or open
                    <code class="px-2 py-0.5 rounded bg-slate-900 text-indigo-300 font-mono text-xs">{{ request()->getSchemeAndHttpHost() }}/download-apk</code>
                    on your phone browser to download and install the latest <span class="text-white font-semibold">Arca-debug.apk</span> immediately.
                </p>
                <div class="pt-2 flex flex-wrap items-center gap-3">
                    <a href="/download-apk" class="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold shadow-lg shadow-indigo-600/30 transition">
                        <span>⬇ Download Arca-debug.apk</span>
                    </a>
                    <span class="text-xs text-slate-400 font-mono">API Base URL: {{ request()->getSchemeAndHttpHost() }}</span>
                </div>
            </div>
            <div class="flex flex-col items-center bg-white p-3 rounded-2xl shadow-lg shrink-0">
                <img
                    src="https://api.qrserver.com/v1/create-qr-code/?size=130x130&data={{ urlencode(request()->getSchemeAndHttpHost() . '/download-apk') }}"
                    alt="Scan to Download APK"
                    class="w-32 h-32 rounded-lg"
                />
                <span class="text-[11px] font-bold text-slate-800 mt-1.5">Scan with Phone Camera</span>
            </div>
        </div>

        @if ($errors->any())
            <div class="mt-6 p-4 rounded-xl bg-rose-900/40 border border-rose-500/40 text-rose-200 text-sm">
                <ul class="list-disc list-inside">
                    @foreach ($errors->all() as $error)
                        <li>{{ $error }}</li>
                    @endforeach
                </ul>
            </div>
        @endif

        <!-- Stats Overview Cards -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5 mt-8">
            <!-- Total Users -->
            <div class="p-5 rounded-2xl bg-slate-800/60 border border-slate-700/60 shadow-lg backdrop-blur">
                <div class="text-xs font-medium uppercase tracking-wider text-slate-400">Total Users</div>
                <div class="text-3xl font-extrabold text-white mt-2">{{ number_format($stats['total_users']) }}</div>
                <div class="text-xs text-indigo-400 mt-2 font-medium">Registered accounts</div>
            </div>

            <!-- Pro Subscribers -->
            <div class="p-5 rounded-2xl bg-slate-800/60 border border-slate-700/60 shadow-lg backdrop-blur">
                <div class="text-xs font-medium uppercase tracking-wider text-slate-400">Pro Subscribers</div>
                <div class="text-3xl font-extrabold text-indigo-400 mt-2">{{ number_format($stats['pro_subscribers']) }}</div>
                <div class="text-xs text-slate-400 mt-2 font-medium">
                    {{ $stats['total_users'] > 0 ? round(($stats['pro_subscribers'] / $stats['total_users']) * 100, 1) : 0 }}% conversion rate
                </div>
            </div>

            <!-- Enrolled Devices -->
            <div class="p-5 rounded-2xl bg-slate-800/60 border border-slate-700/60 shadow-lg backdrop-blur">
                <div class="text-xs font-medium uppercase tracking-wider text-slate-400">Enrolled Devices</div>
                <div class="text-3xl font-extrabold text-white mt-2">{{ number_format($stats['enrolled_devices']) }}</div>
                <div class="text-xs text-slate-400 mt-2 font-medium">
                    {{ number_format($stats['active_devices']) }} active · {{ number_format($stats['user_linked_devices']) }} linked · {{ number_format($stats['guest_devices']) }} guest
                </div>
            </div>

            <!-- Synced Spaces -->
            <div class="p-5 rounded-2xl bg-slate-800/60 border border-slate-700/60 shadow-lg backdrop-blur">
                <div class="text-xs font-medium uppercase tracking-wider text-slate-400">Synced Spaces</div>
                <div class="text-3xl font-extrabold text-white mt-2">{{ number_format($stats['synced_spaces']) }}</div>
                <div class="text-xs text-slate-400 mt-2 font-medium">Encrypted cloud spaces</div>
            </div>

            <!-- Opaque Ciphertext Bytes -->
            <div class="p-5 rounded-2xl bg-slate-800/60 border border-slate-700/60 shadow-lg backdrop-blur">
                <div class="text-xs font-medium uppercase tracking-wider text-slate-400">Opaque Ciphertext Stored</div>
                <div class="text-2xl font-extrabold text-emerald-400 mt-2">{{ $stats['formatted_ciphertext_bytes'] }}</div>
                <div class="text-xs text-slate-400 mt-2 font-mono">{{ number_format($stats['ciphertext_bytes']) }} bytes</div>
            </div>

            <!-- Active Announcements / Ads -->
            <div class="p-5 rounded-2xl bg-slate-800/60 border border-slate-700/60 shadow-lg backdrop-blur">
                <div class="text-xs font-medium uppercase tracking-wider text-slate-400">Active Announcements / Ads</div>
                <div class="text-3xl font-extrabold text-amber-400 mt-2">{{ number_format($stats['active_announcements']) }}</div>
                <div class="text-xs text-slate-400 mt-2 font-medium">Currently served in feed</div>
            </div>

            <!-- Public Record Snapshots -->
            <div class="p-5 rounded-2xl bg-slate-800/60 border border-slate-700/60 shadow-lg backdrop-blur">
                <div class="text-xs font-medium uppercase tracking-wider text-slate-400">Public Record Snapshots</div>
                <div class="text-3xl font-extrabold text-purple-400 mt-2">{{ number_format($stats['public_snapshots']) }}</div>
                <div class="text-xs text-slate-400 mt-2 font-medium">Revocable shared links</div>
            </div>

            <!-- Architecture Badge Card -->
            <div class="p-5 rounded-2xl bg-slate-800/60 border border-indigo-500/30 shadow-lg backdrop-blur flex flex-col justify-between">
                <div class="text-xs font-medium uppercase tracking-wider text-indigo-400">Default Storage Mode</div>
                <div class="text-xl font-bold text-white mt-1">arca_sync (Cloud DB)</div>
                <div class="text-xs text-slate-400 mt-2">Local-only supported per space</div>
            </div>
        </div>

        <!-- Two Column Layout: Create Form + Announcement List -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8 mt-10">
            <!-- Form to Create Announcement -->
            <div class="lg:col-span-1 bg-slate-800/60 border border-slate-700/60 rounded-2xl p-6 shadow-xl">
                <h2 class="text-lg font-bold text-white mb-1">Create Announcement / Banner</h2>
                <p class="text-xs text-slate-400 mb-5">Broadcast messages, promotions, or system alerts to clients.</p>

                <form action="/admin/announcements" method="POST" class="space-y-4">
                    @csrf
                    <div>
                        <label for="title" class="block text-xs font-medium text-slate-300 uppercase tracking-wider mb-1">Title</label>
                        <input type="text" name="title" id="title" required value="{{ old('title') }}" placeholder="e.g. Winter Sale: Arca Pro 50% Off"
                               class="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-white text-sm focus:outline-none focus:border-indigo-500">
                    </div>

                    <div>
                        <label for="body" class="block text-xs font-medium text-slate-300 uppercase tracking-wider mb-1">Body</label>
                        <textarea name="body" id="body" rows="3" required placeholder="Announcement content details..."
                                  class="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-white text-sm focus:outline-none focus:border-indigo-500">{{ old('body') }}</textarea>
                    </div>

                    <div class="grid grid-cols-2 gap-3">
                        <div>
                            <label for="cta_label" class="block text-xs font-medium text-slate-300 uppercase tracking-wider mb-1">CTA Label</label>
                            <input type="text" name="cta_label" id="cta_label" value="{{ old('cta_label') }}" placeholder="Upgrade Now"
                                   class="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-white text-sm focus:outline-none focus:border-indigo-500">
                        </div>
                        <div>
                            <label for="cta_url" class="block text-xs font-medium text-slate-300 uppercase tracking-wider mb-1">CTA URL</label>
                            <input type="url" name="cta_url" id="cta_url" value="{{ old('cta_url') }}" placeholder="https://arca.app/pro"
                                   class="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-white text-sm focus:outline-none focus:border-indigo-500">
                        </div>
                    </div>

                    <div class="grid grid-cols-2 gap-3">
                        <div>
                            <label for="placement" class="block text-xs font-medium text-slate-300 uppercase tracking-wider mb-1">Placement</label>
                            <select name="placement" id="placement" class="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-white text-sm focus:outline-none focus:border-indigo-500">
                                <option value="home_banner">home_banner</option>
                                <option value="settings_card">settings_card</option>
                                <option value="announcement_modal">announcement_modal</option>
                            </select>
                        </div>
                        <div>
                            <label for="priority" class="block text-xs font-medium text-slate-300 uppercase tracking-wider mb-1">Priority</label>
                            <input type="number" name="priority" id="priority" value="{{ old('priority', 0) }}"
                                   class="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-white text-sm focus:outline-none focus:border-indigo-500">
                        </div>
                    </div>

                    <div class="grid grid-cols-2 gap-3">
                        <div>
                            <label for="target_platform" class="block text-xs font-medium text-slate-300 uppercase tracking-wider mb-1">Target Platform</label>
                            <select name="target_platform" id="target_platform" class="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-white text-sm focus:outline-none focus:border-indigo-500">
                                <option value="all">all</option>
                                <option value="ios">ios</option>
                                <option value="android">android</option>
                            </select>
                        </div>
                        <div>
                            <label for="target_tier" class="block text-xs font-medium text-slate-300 uppercase tracking-wider mb-1">Target Tier</label>
                            <select name="target_tier" id="target_tier" class="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-white text-sm focus:outline-none focus:border-indigo-500">
                                <option value="all">all</option>
                                <option value="free">free</option>
                                <option value="pro">pro</option>
                            </select>
                        </div>
                    </div>

                    <div class="flex items-center gap-2 pt-2">
                        <input type="checkbox" name="is_active" id="is_active" value="1" checked
                               class="rounded bg-slate-900 border-slate-700 text-indigo-600 focus:ring-indigo-500 w-4 h-4">
                        <label for="is_active" class="text-sm font-medium text-slate-300">Set active immediately</label>
                    </div>

                    <button type="submit" class="w-full py-2.5 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-sm transition shadow-lg shadow-indigo-600/30">
                        Publish Announcement
                    </button>
                </form>
            </div>

            <!-- List of Announcements with Toggle Buttons -->
            <div class="lg:col-span-2 bg-slate-800/60 border border-slate-700/60 rounded-2xl p-6 shadow-xl">
                <div class="flex items-center justify-between mb-4">
                    <div>
                        <h2 class="text-lg font-bold text-white">App Announcements & Ads</h2>
                        <p class="text-xs text-slate-400">Total {{ count($announcements) }} announcements recorded</p>
                    </div>
                </div>

                @if ($announcements->isEmpty())
                    <div class="py-12 text-center text-slate-400 text-sm">
                        No announcements created yet.
                    </div>
                @else
                    <div class="overflow-x-auto">
                        <table class="w-full text-left text-sm">
                            <thead>
                                <tr class="border-b border-slate-700 text-slate-400 text-xs uppercase tracking-wider">
                                    <th class="py-3 px-3">Title</th>
                                    <th class="py-3 px-3">Placement</th>
                                    <th class="py-3 px-3">Platform</th>
                                    <th class="py-3 px-3">Tier</th>
                                    <th class="py-3 px-3">Priority</th>
                                    <th class="py-3 px-3">Status</th>
                                    <th class="py-3 px-3 text-right">Action</th>
                                </tr>
                            </thead>
                            <tbody class="divide-y divide-slate-700/60">
                                @foreach ($announcements as $announcement)
                                    <tr class="hover:bg-slate-700/30 transition">
                                        <td class="py-3 px-3 font-medium text-white max-w-[200px] truncate" title="{{ $announcement->title }}">
                                            {{ $announcement->title }}
                                        </td>
                                        <td class="py-3 px-3 text-slate-300 font-mono text-xs">
                                            {{ $announcement->placement }}
                                        </td>
                                        <td class="py-3 px-3">
                                            <span class="inline-flex px-2 py-0.5 rounded text-xs font-semibold bg-slate-700 text-slate-200">
                                                {{ $announcement->target_platform }}
                                            </span>
                                        </td>
                                        <td class="py-3 px-3">
                                            <span class="inline-flex px-2 py-0.5 rounded text-xs font-semibold {{ $announcement->target_tier === 'pro' ? 'bg-indigo-900 text-indigo-200' : ($announcement->target_tier === 'free' ? 'bg-amber-900 text-amber-200' : 'bg-slate-700 text-slate-200') }}">
                                                {{ $announcement->target_tier }}
                                            </span>
                                        </td>
                                        <td class="py-3 px-3 text-slate-300 font-mono text-xs">
                                            {{ $announcement->priority }}
                                        </td>
                                        <td class="py-3 px-3">
                                            @if ($announcement->is_active)
                                                <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-900/50 text-emerald-300 border border-emerald-500/30">
                                                    <span class="w-1.5 h-1.5 rounded-full bg-emerald-400"></span> Active
                                                </span>
                                            @else
                                                <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-slate-700/50 text-slate-400 border border-slate-600/30">
                                                    <span class="w-1.5 h-1.5 rounded-full bg-slate-400"></span> Inactive
                                                </span>
                                            @endif
                                        </td>
                                        <td class="py-3 px-3 text-right">
                                            <form action="/admin/announcements/{{ $announcement->id }}/toggle" method="POST" class="inline">
                                                @csrf
                                                <button type="submit" class="text-xs font-semibold px-3 py-1.5 rounded-lg {{ $announcement->is_active ? 'bg-rose-900/50 text-rose-300 hover:bg-rose-900 border border-rose-500/30' : 'bg-emerald-900/50 text-emerald-300 hover:bg-emerald-900 border border-emerald-500/30' }} transition">
                                                    {{ $announcement->is_active ? 'Deactivate' : 'Activate' }}
                                                </button>
                                            </form>
                                        </td>
                                    </tr>
                                @endforeach
                            </tbody>
                        </table>
                    </div>
                @endif
            </div>
        </div>

        <!-- Recent Devices Table -->
        <div class="bg-slate-800/60 border border-slate-700/60 rounded-2xl p-6 shadow-xl mt-10">
            <div class="flex items-center justify-between mb-4">
                <div>
                    <h2 class="text-lg font-bold text-white">Registered & Guest Devices</h2>
                    <p class="text-xs text-slate-400">Recent devices synced, assigned to users or guest/unassigned</p>
                </div>
                <div class="text-xs text-slate-400">
                    <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium bg-indigo-950/60 border border-indigo-500/30 text-indigo-300">
                        {{ number_format($stats['user_linked_devices']) }} Linked / {{ number_format($stats['guest_devices']) }} Guest
                    </span>
                </div>
            </div>

            @php
                $devicesList = $recentDevices ?? $recent_devices ?? collect();
            @endphp

            @if ($devicesList->isEmpty())
                <div class="py-8 text-center text-slate-400 text-sm">
                    No registered devices yet.
                </div>
            @else
                <div class="overflow-x-auto">
                    <table class="w-full text-left text-sm">
                        <thead>
                            <tr class="border-b border-slate-700 text-slate-400 text-xs uppercase tracking-wider">
                                <th class="py-3 px-3">Device Name</th>
                                <th class="py-3 px-3">Platform</th>
                                <th class="py-3 px-3">Device Token</th>
                                <th class="py-3 px-3">User</th>
                                <th class="py-3 px-3">Last Synced At</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-slate-700/60">
                            @foreach ($devicesList as $device)
                                <tr class="hover:bg-slate-700/30 transition">
                                    <td class="py-3 px-3 font-medium text-white">
                                        {{ $device->device_name }}
                                    </td>
                                    <td class="py-3 px-3">
                                        <span class="inline-flex px-2 py-0.5 rounded text-xs font-semibold bg-slate-700 text-slate-200">
                                            {{ $device->platform }}
                                        </span>
                                    </td>
                                    <td class="py-3 px-3 text-slate-300 font-mono text-xs max-w-[200px] truncate" title="{{ $device->device_token }}">
                                        {{ $device->device_token ?? '—' }}
                                    </td>
                                    <td class="py-3 px-3">
                                        @if ($device->user)
                                            <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium bg-emerald-950/60 text-emerald-300 border border-emerald-500/30">
                                                {{ $device->user->email }}
                                            </span>
                                        @else
                                            <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium bg-amber-950/60 text-amber-300 border border-amber-500/30">
                                                Unassigned / Pre-Login
                                            </span>
                                        @endif
                                    </td>
                                    <td class="py-3 px-3 text-slate-400 text-xs">
                                        {{ $device->last_synced_at ? $device->last_synced_at->diffForHumans() : 'Never' }}
                                    </td>
                                </tr>
                            @endforeach
                        </tbody>
                    </table>
                </div>
            @endif
        </div>
    </div>
</body>
</html>
