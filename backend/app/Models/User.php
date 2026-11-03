<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Str;

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasFactory, Notifiable;

    /**
     * The attributes that are mass assignable.
     *
     * @var list<string>
     */
    protected $fillable = [
        'name',
        'email',
        'password',
        'uuid',
        'subscription_tier',
        'subscription_state',
        'revenuecat_app_user_id',
        'subscription_product_id',
        'subscription_expires_at',
        'remote_storage_bytes_used',
        'is_admin',
        'api_token',
    ];

    /**
     * The attributes that should be hidden for serialization.
     *
     * @var list<string>
     */
    protected $hidden = [
        'password',
        'remember_token',
        'api_token',
    ];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'subscription_expires_at' => 'datetime',
            'remote_storage_bytes_used' => 'integer',
            'is_admin' => 'boolean',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (User $user) {
            if (empty($user->uuid)) {
                $user->uuid = (string) Str::uuid();
            }
            if (empty($user->subscription_tier)) {
                $user->subscription_tier = 'free';
            }
            if (empty($user->subscription_state)) {
                $user->subscription_state = 'active';
            }
        });
    }

    public function enrolledDevices(): HasMany
    {
        return $this->hasMany(EnrolledDevice::class);
    }

    public function syncedSpaces(): HasMany
    {
        return $this->hasMany(SyncedSpace::class);
    }

    public function syncOperations(): HasMany
    {
        return $this->hasMany(SyncOperation::class);
    }

    public function encryptedAttachments(): HasMany
    {
        return $this->hasMany(EncryptedAttachment::class);
    }

    public function publicRecordSnapshots(): HasMany
    {
        return $this->hasMany(PublicRecordSnapshot::class);
    }

    public function maxAllowedDevices(): int
    {
        $tier = $this->subscription_tier ?: 'free';
        return (int) config("arca.quotas.{$tier}.max_devices", 2);
    }

    public function maxAllowedStorageBytes(): int
    {
        $tier = $this->subscription_tier ?: 'free';
        return (int) config("arca.quotas.{$tier}.max_storage_bytes", 262144000);
    }

    public function activeEnrolledDevicesCount(): int
    {
        return $this->enrolledDevices()->whereNull('revoked_at')->count();
    }

    public function postExpiryPolicy(): array
    {
        $maxStorage = $this->maxAllowedStorageBytes();
        $maxDevices = $this->maxAllowedDevices();
        $activeDevices = $this->activeEnrolledDevicesCount();

        $isOverStorageQuota = $this->remote_storage_bytes_used > $maxStorage;
        $isOverDeviceLimit = $activeDevices > $maxDevices;
        $isExpired = in_array($this->subscription_state, ['expired', 'revoked_or_refunded'], true);

        $canPush = ! $isOverStorageQuota && ! $isOverDeviceLimit && ! $isExpired;
        $canPull = $this->subscription_state !== 'revoked_or_refunded';
        $canEnroll = $activeDevices < $maxDevices;

        return [
            'canLocalRead' => true,
            'canLocalWrite' => true,
            'canLocalExport' => true,
            'canPullRemoteSync' => $canPull,
            'canPushRemoteSync' => $canPush,
            'canEnrollAdditionalDevices' => $canEnroll,
            'canUploadNewAttachments' => $canPush && ! $isOverStorageQuota,
            'isOverStorageQuota' => $isOverStorageQuota,
            'isOverDeviceLimit' => $isOverDeviceLimit,
            'remoteRetentionDaysAfterExpiry' => (int) config('arca.remote_retention_days', 90),
            'subscription_tier' => $this->subscription_tier,
            'subscription_state' => $this->subscription_state,
        ];
    }
}
