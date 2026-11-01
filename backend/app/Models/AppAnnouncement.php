<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class AppAnnouncement extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'app_announcements';

    protected $fillable = [
        'id',
        'title',
        'body',
        'cta_label',
        'cta_url',
        'placement',
        'target_platform',
        'target_tier',
        'is_active',
        'starts_at',
        'ends_at',
        'priority',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'starts_at' => 'datetime',
            'ends_at' => 'datetime',
            'priority' => 'integer',
        ];
    }
}
