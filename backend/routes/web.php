<?php

use App\Http\Controllers\AdminDashboardController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// Admin Web Dashboard & Wireless APK Installer
Route::get('/admin', [AdminDashboardController::class, 'index']);
Route::get('/download-apk', [AdminDashboardController::class, 'downloadApk']);
Route::post('/admin/announcements', [AdminDashboardController::class, 'storeAnnouncement']);
Route::post('/admin/announcements/{id}/toggle', [AdminDashboardController::class, 'toggleAnnouncement']);
