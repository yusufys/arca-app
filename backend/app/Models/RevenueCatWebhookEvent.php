<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class RevenueCatWebhookEvent extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'revenuecat_webhook_events';

    protected $fillable = [
        'id',
        'event_id',
        'event_type',
        'app_user_id',
        'product_id',
        'payload_json',
        'processed_at',
    ];

    protected function casts(): array
    {
        return [
            'payload_json' => 'array',
            'processed_at' => 'datetime',
        ];
    }
}
