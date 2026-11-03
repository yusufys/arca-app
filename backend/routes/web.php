<?php

use App\Http\Controllers\AdminDashboardController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::middleware(['throttle:60,1', 'auth.basic', 'can:administer-arca'])->group(function () {
    Route::get('/admin', [AdminDashboardController::class, 'index']);
    Route::post('/admin/announcements', [AdminDashboardController::class, 'storeAnnouncement']);
    Route::post('/admin/announcements/{id}/toggle', [AdminDashboardController::class, 'toggleAnnouncement']);
    Route::get('/download-apk', [AdminDashboardController::class, 'downloadApk']);
});
