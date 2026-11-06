<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Default Space Storage Mode
    |--------------------------------------------------------------------------
    | 'arca_sync': Encrypted cloud sync (Cloud DB) is default.
    | 'local_only': On-device SQLite only; supported per Space and default for sensitive medical spaces.
    */
    'default_space_storage_mode' => env('ARCA_DEFAULT_STORAGE_MODE', 'arca_sync'),
    'sensitive_medical_default_mode' => env('ARCA_SENSITIVE_MEDICAL_DEFAULT_MODE', 'local_only'),
    'local_only_available' => (bool) env('ARCA_LOCAL_ONLY_AVAILABLE', true),

    /*
    |--------------------------------------------------------------------------
    | Storage and Device Quotas
    |--------------------------------------------------------------------------
    | Free tier: 2 devices, 250 MB ciphertext storage (262,144,000 bytes)
    | Pro tier: 10 devices, 1 GB ciphertext storage (1,073,741,824 bytes)
    */
    'quotas' => [
        'free' => [
            'max_devices' => 2,
            'max_storage_bytes' => 262144000, // 250 MB
        ],
        'pro' => [
            'max_devices' => 10,
            'max_storage_bytes' => 1073741824, // 1 GB
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Remote Retention After Subscription Expiry
    |--------------------------------------------------------------------------
    | Grace period in days before remote ciphertext is permanently purged.
    */
    'remote_retention_days' => (int) env('ARCA_REMOTE_RETENTION_DAYS', 90),

    /*
    |--------------------------------------------------------------------------
    | RevenueCat Webhook & Entitlements
    |--------------------------------------------------------------------------
    */
    'revenuecat' => [
        'webhook_secret' => env('REVENUECAT_WEBHOOK_SECRET'),
        'pro_entitlement_id' => env('REVENUECAT_PRO_ENTITLEMENT_ID', 'arca_app_pro'),
        'server_api_key' => env('REVENUECAT_SERVER_API_KEY'),
        'environment' => env('REVENUECAT_ENVIRONMENT', 'PRODUCTION'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Encrypted Attachments Disk
    |--------------------------------------------------------------------------
    */
    'attachments_disk' => env('ARCA_ATTACHMENTS_DISK', 'r2'),
];
