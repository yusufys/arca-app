<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

class ApiSession extends Model
{
    protected $primaryKey = 'token_hash';

    protected $keyType = 'string';

    public $incrementing = false;

    protected $fillable = ['token_hash', 'user_id', 'device_id'];

    protected $hidden = ['token_hash'];

    public static function issue(User $user, ?string $deviceId = null): string
    {
        $secret = Str::random(64);
        self::create(['token_hash' => hash('sha256', $secret), 'user_id' => $user->id, 'device_id' => $deviceId]);

        return $secret;
    }
}
