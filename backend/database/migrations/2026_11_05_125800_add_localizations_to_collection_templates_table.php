<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('collection_templates', function (Blueprint $table): void {
            $table->json('localizations')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('collection_templates', function (Blueprint $table): void {
            $table->dropColumn('localizations');
        });
    }
};
