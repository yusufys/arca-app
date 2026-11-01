<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PublicRecordSnapshot extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'public_record_snapshots';

    protected $fillable = [
        'id',
        'user_id',
        'space_id',
        'record_id',
        'share_token',
        'selected_fields_json',
        'revoked_at',
        'expires_at',
    ];

    protected function casts(): array
    {
        return [
            'selected_fields_json' => 'array',
            'revoked_at' => 'datetime',
            'expires_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
