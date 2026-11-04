<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('synced_spaces', function (Blueprint $table) {
            $table->unsignedInteger('privacy_generation')->default(0);
            $table->json('privacy_rules_json')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('synced_spaces', fn (Blueprint $table) => $table->dropColumn(['privacy_generation', 'privacy_rules_json']));
    }
};
