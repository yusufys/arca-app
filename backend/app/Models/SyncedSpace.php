<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class SyncedSpace extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'synced_spaces';

    protected $fillable = [
        'id',
        'user_id',
        'storage_mode',
        'current_key_version',
        'wrapped_space_keys_json',
        'privacy_generation',
        'privacy_rules_json',
        'ciphertext_bytes',
        'deleted_at',
    ];

    protected function casts(): array
    {
        return [
            'current_key_version' => 'integer',
            'wrapped_space_keys_json' => 'array',
            'privacy_generation' => 'integer',
            'privacy_rules_json' => 'array',
            'ciphertext_bytes' => 'integer',
            'deleted_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function syncOperations(): HasMany
    {
        return $this->hasMany(SyncOperation::class, 'space_id');
    }

    public function encryptedAttachments(): HasMany
    {
        return $this->hasMany(EncryptedAttachment::class, 'space_id');
    }
}
