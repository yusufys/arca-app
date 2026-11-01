<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SyncOperation extends Model
{
    use HasFactory;

    protected $table = 'sync_operations';
    protected $primaryKey = 'server_cursor';
    public $incrementing = true;
    protected $keyType = 'int';

    protected $fillable = [
        'operation_id',
        'space_id',
        'user_id',
        'device_id',
        'entity_id',
        'entity_type',
        'base_revision',
        'new_revision',
        'key_version',
        'schema_version',
        'ciphertext_bytes',
        'encrypted_envelope_json',
    ];

    protected function casts(): array
    {
        return [
            'server_cursor' => 'integer',
            'base_revision' => 'integer',
            'new_revision' => 'integer',
            'key_version' => 'integer',
            'schema_version' => 'integer',
            'ciphertext_bytes' => 'integer',
            'encrypted_envelope_json' => 'array',
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
