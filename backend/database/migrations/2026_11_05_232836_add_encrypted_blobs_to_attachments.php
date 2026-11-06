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
        Schema::table('encrypted_attachments', function (Blueprint $table) {
            $table->uuid('reference_id')->nullable();
            $table->uuid('collection_id')->nullable()->index();
            $table->longText('encrypted_blob')->nullable();
            $table->unique(['space_id', 'reference_id']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('encrypted_attachments', function (Blueprint $table) {
            $table->dropUnique(['space_id', 'reference_id']);
            $table->dropColumn(['reference_id', 'collection_id', 'encrypted_blob']);
        });
    }
};
