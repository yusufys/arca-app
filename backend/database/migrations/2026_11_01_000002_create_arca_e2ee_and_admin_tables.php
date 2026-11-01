<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('enrolled_devices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('device_name');
            $table->string('platform'); // 'ios' | 'android' | 'macos'
            $table->text('public_key_x25519');
            $table->timestamp('last_synced_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();
        });

        Schema::create('synced_spaces', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('storage_mode')->default('arca_sync'); // 'arca_sync' | 'local_only'
            $table->unsignedInteger('current_key_version')->default(1);
            $table->json('wrapped_space_keys_json')->nullable();
            $table->unsignedBigInteger('ciphertext_bytes')->default(0);
            $table->timestamp('deleted_at')->nullable();
            $table->timestamps();
        });

        Schema::create('sync_operations', function (Blueprint $table) {
            $table->id('server_cursor'); // bigIncrements primary key
            $table->uuid('operation_id')->unique();
            $table->uuid('space_id')->index();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->uuid('device_id');
            $table->uuid('entity_id')->index();
            $table->string('entity_type'); // 'schema' | 'record' | 'tombstone'
            $table->unsignedInteger('base_revision')->nullable();
            $table->unsignedInteger('new_revision');
            $table->unsignedInteger('key_version');
            $table->unsignedInteger('schema_version');
            $table->unsignedBigInteger('ciphertext_bytes')->default(0);
            $table->json('encrypted_envelope_json'); // nonceBase64, ciphertextAndTagBase64, aadSummary; ZERO plaintext!
            $table->timestamps();
        });

        Schema::create('encrypted_attachments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('space_id')->index();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->uuid('record_id')->index();
            $table->unsignedBigInteger('byte_size');
            $table->string('ciphertext_sha256');
            $table->string('storage_disk')->default('r2');
            $table->string('object_key');
            $table->unsignedInteger('key_version')->default(1);
            $table->timestamps();
        });

        Schema::create('app_announcements', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('title');
            $table->text('body');
            $table->string('cta_label')->nullable();
            $table->string('cta_url')->nullable();
            $table->string('placement')->default('home_banner'); // 'home_banner' | 'settings_card' | 'announcement_modal'
            $table->string('target_platform')->default('all'); // 'all' | 'ios' | 'android'
            $table->string('target_tier')->default('all'); // 'all' | 'free' | 'pro'
            $table->boolean('is_active')->default(true);
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('ends_at')->nullable();
            $table->integer('priority')->default(0);
            $table->timestamps();
        });

        Schema::create('public_record_snapshots', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->uuid('space_id');
            $table->uuid('record_id');
            $table->string('share_token')->unique();
            $table->json('selected_fields_json');
            $table->timestamp('revoked_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();
        });

        Schema::create('revenuecat_webhook_events', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('event_id')->unique();
            $table->string('event_type');
            $table->string('app_user_id')->index();
            $table->string('product_id')->nullable();
            $table->json('payload_json');
            $table->timestamp('processed_at');
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('revenuecat_webhook_events');
        Schema::dropIfExists('public_record_snapshots');
        Schema::dropIfExists('app_announcements');
        Schema::dropIfExists('encrypted_attachments');
        Schema::dropIfExists('sync_operations');
        Schema::dropIfExists('synced_spaces');
        Schema::dropIfExists('enrolled_devices');
    }
};
