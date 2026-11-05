<?php

namespace Tests\Feature;

use App\CollectionSchemaContract;
use App\Models\CollectionTemplate;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CollectionCatalogMigrationTest extends TestCase
{
    use RefreshDatabase;

    public function test_migration_seeds_only_valid_starters_and_preserves_edits_when_repeated(): void
    {
        $this->getJson('/api/v1/collection-templates')->assertOk()->assertJsonCount(3, 'templates')
            ->assertJsonPath('templates.0.id', 'vehicle_maintenance')
            ->assertJsonPath('templates.1.id', 'home_inventory')
            ->assertJsonPath('templates.2.id', 'warranties');
        foreach (CollectionTemplate::all() as $template) {
            $this->assertSame($template->schema_definition, app(CollectionSchemaContract::class)->validate($template->schema_definition));
        }
        CollectionTemplate::where('slug', 'vehicle_maintenance')->firstOrFail()->update(['subtitle' => 'Operator edit', 'is_active' => false]);
        $migration = require database_path('migrations/2026_11_05_003934_seed_initial_collection_templates.php');
        $migration->up();

        $this->assertDatabaseCount('collection_templates', 3);
        $this->assertDatabaseHas('collection_templates', ['slug' => 'vehicle_maintenance', 'subtitle' => 'Operator edit', 'is_active' => false]);
    }
}
