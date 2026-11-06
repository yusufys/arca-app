<?php

use App\Http\Controllers\Api\V1\AppFeedController;
use App\Http\Controllers\Api\V1\AttachmentController;
use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\CollectionCatalogController;
use App\Http\Controllers\Api\V1\DeviceController;
use App\Http\Controllers\Api\V1\PublicSnapshotController;
use App\Http\Controllers\Api\V1\RevenueCatWebhookController;
use App\Http\Controllers\Api\V1\SyncController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Arca API V1 Routes
|--------------------------------------------------------------------------
*/

Route::prefix('v1')->middleware('throttle:120,1')->group(function () {
    // Public Auth endpoints
    Route::post('/auth/register', [AuthController::class, 'register'])->middleware('throttle:10,1,auth');
    Route::post('/auth/login', [AuthController::class, 'login'])->middleware('throttle:10,1,auth');

    // Public Anonymous & Authenticated Device Registration
    Route::post('/devices/register', [DeviceController::class, 'registerDevice']);

    // Public App announcements / ad feed
    Route::get('/app-feed', [AppFeedController::class, 'index']);

    Route::get('/collection-templates', [CollectionCatalogController::class, 'index']);
    Route::get('/collection-schema', [CollectionCatalogController::class, 'schema']);
    Route::post('/collection-prompt', [CollectionCatalogController::class, 'prompt'])->middleware('throttle:30,1');

    // RevenueCat Webhook (verified via Bearer secret)
    Route::post('/webhooks/revenuecat', [RevenueCatWebhookController::class, 'handle']);

    // Public Record Snapshots
    Route::get('/snapshots/{shareToken}', [PublicSnapshotController::class, 'show']);

    // Authenticated Endpoints (Bearer api_token)
    Route::middleware('arca.auth')->group(function () {
        Route::delete('/account', [AuthController::class, 'destroy']);
        Route::get('/auth/me', [AuthController::class, 'me']);

        // Devices
        Route::get('/devices', [DeviceController::class, 'index']);
        Route::post('/devices/enroll', [DeviceController::class, 'enroll']);
        Route::post('/devices/{deviceId}/revoke', [DeviceController::class, 'revoke']);

        Route::get('/sync/recovery', [SyncController::class, 'recovery']);
        Route::post('/sync/recovery', [SyncController::class, 'storeRecovery']);
        Route::get('/spaces', [SyncController::class, 'index']);
        Route::get('/spaces/{spaceId}/keys', [SyncController::class, 'keys']);
        Route::post('/spaces/{spaceId}/keys', [SyncController::class, 'storeKey']);

        Route::get('/spaces/{spaceId}/privacy', [SyncController::class, 'privacy']);
        Route::post('/spaces/{spaceId}/privacy', [SyncController::class, 'updatePrivacy']);

        // E2EE Sync operations & spaces
        Route::post('/spaces/{spaceId}/register', [SyncController::class, 'registerSpace']);
        Route::post('/spaces/{spaceId}/push', [SyncController::class, 'push']);
        Route::get('/spaces/{spaceId}/pull', [SyncController::class, 'pull']);
        Route::post('/spaces/{spaceId}/migrate-mode', [SyncController::class, 'migrateMode']);

        // Encrypted Attachments
        Route::post('/spaces/{spaceId}/attachments', [AttachmentController::class, 'store']);
        Route::get('/spaces/{spaceId}/attachments/{attachmentId}', [AttachmentController::class, 'show']);

        // Public Snapshots Management
        Route::post('/snapshots', [PublicSnapshotController::class, 'store']);
        Route::post('/snapshots/{shareToken}/revoke', [PublicSnapshotController::class, 'revoke']);
    });
});
