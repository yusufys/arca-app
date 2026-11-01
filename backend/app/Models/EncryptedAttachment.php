<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class EncryptedAttachment extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'encrypted_attachments';

    protected $fillable = [
        'id',
        'space_id',
        'user_id',
        'record_id',
        'byte_size',
        'ciphertext_sha256',
        'storage_disk',
        'object_key',
        'key_version',
    ];

    protected function casts(): array
    {
        return [
            'byte_size' => 'integer',
            'key_version' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function space(): BelongsTo
    {
        return $this->belongsTo(SyncedSpace::class, 'space_id');
    }
}
