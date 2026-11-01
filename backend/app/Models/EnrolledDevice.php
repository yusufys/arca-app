<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class EnrolledDevice extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'enrolled_devices';

    protected $fillable = [
        'id',
        'user_id',
        'device_token',
        'device_name',
        'platform',
        'app_version',
        'public_key_x25519',
        'last_synced_at',
        'revoked_at',
    ];

    protected $appends = [
        'is_associated',
    ];

    public function getIsAssociatedAttribute(): bool
    {
        return $this->user_id !== null;
    }

    protected function casts(): array
    {
        return [
            'last_synced_at' => 'datetime',
            'revoked_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
