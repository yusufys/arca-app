<?php

namespace Database\Seeders;

use App\Models\AppAnnouncement;
use App\Models\User;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        // 1. Seed Admin User
        User::firstOrCreate(
            ['email' => 'admin@arca.app'],
            [
                'name' => 'Arca Admin',
                'password' => Hash::make('ArcaAdmin2026!'),
                'uuid' => (string) Str::uuid(),
                'subscription_tier' => 'pro',
                'subscription_state' => 'active',
                'is_admin' => true,
                'api_token' => Str::random(60),
                'remote_storage_bytes_used' => 0,
            ]
        );

        // 2. Seed Default Active App Announcement Banner
        AppAnnouncement::firstOrCreate(
            ['title' => 'Welcome to Arca Zero-Knowledge Sync'],
            [
                'body' => 'All spaces, schemas, and record fields are end-to-end encrypted locally on your device with X25519 & AES-GCM before syncing.',
                'cta_label' => 'Learn More',
                'cta_url' => 'https://arca.app/security',
                'placement' => 'home_banner',
                'target_platform' => 'all',
                'target_tier' => 'all',
                'is_active' => true,
                'priority' => 10,
                'starts_at' => now()->subDay(),
            ]
        );
    }
}
