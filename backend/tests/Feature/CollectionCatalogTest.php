<?php

namespace Tests\Feature;

use App\CollectionSchemaContract;
use App\Models\CollectionTemplate;
use App\Models\User;
use Database\Seeders\CollectionTemplateSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

class CollectionCatalogTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        CollectionTemplate::query()->delete();
    }

    public function test_public_catalog_only_returns_active_templates_in_stable_order(): void
    {
        CollectionTemplate::factory()->create(['slug' => 'hidden']);
        CollectionTemplate::factory()->create(['slug' => 'second', 'is_active' => true, 'sort_order' => 20]);
        $first = CollectionTemplate::factory()->create(['slug' => 'first', 'is_active' => true, 'sort_order' => 10]);

        $this->getJson('/api/v1/collection-templates')->assertOk()->assertExactJson([
            'version' => 1,
            'templates' => [
                ['id' => 'first', 'subtitle' => $first->subtitle, 'schema' => $first->schema_definition],
                ['id' => 'second', 'subtitle' => $first->subtitle, 'schema' => $first->schema_definition],
            ],
        ]);
    }

    public function test_translated_catalog_is_validated_and_preserved_on_legacy_admin_updates(): void
    {
        $this->actingAs(User::factory()->create(['is_admin' => true]));
        $payload = $this->payload();
        $payload['localizations_json'] = json_encode(['ar' => [
            'subtitle' => 'مقتنيات المنزل',
            'schema' => ['name' => 'مقتنيات', 'fields' => [['label' => 'الاسم', 'type' => 'short_text']]],
        ]]);
        $this->postJson('/admin/collection-templates', $payload)->assertCreated();
        $template = CollectionTemplate::where('slug', 'equipment')->firstOrFail();
        $this->getJson('/api/v1/collection-templates')->assertOk()
            ->assertJsonPath('templates.0.localizations.ar.schema.fields.0.label', 'الاسم');

        unset($payload['localizations_json']);
        $this->postJson('/admin/collection-templates/'.$template->id, $payload)->assertOk();
        $this->assertSame('مقتنيات', $template->fresh()->localizations['ar']['schema']['name']);

        $payload['localizations_json'] = json_encode(['ar' => [
            'subtitle' => 'Invalid', 'schema' => ['name' => 'Invalid', 'fields' => [['label' => 'URL', 'type' => 'url']]],
        ]]);
        $this->postJson('/admin/collection-templates/'.$template->id, $payload)->assertUnprocessable();
        $this->assertSame('مقتنيات', $template->fresh()->localizations['ar']['schema']['name']);
    }

    public function test_prompt_uses_requested_language_without_translating_schema_keys(): void
    {
        foreach (['ar' => 'Arabic', 'tr' => 'Turkish', 'en' => 'English'] as $locale => $name) {
            $response = $this->postJson('/api/v1/collection-prompt', ['intent' => 'Home', 'language' => $locale])->assertOk();
            $this->assertStringContainsString('in '.$name, $response->json('prompt'));
            $this->assertStringContainsString('short_text', $response->json('prompt'));
        }
        $this->postJson('/api/v1/collection-prompt', ['intent' => 'Home', 'language' => 'xx'])->assertUnprocessable();
    }

    public function test_catalog_can_be_empty_without_inserting_defaults(): void
    {
        $this->getJson('/api/v1/collection-templates')->assertOk()->assertExactJson(['version' => 1, 'templates' => []]);
        $this->assertDatabaseCount('collection_templates', 0);
    }

    public function test_admin_can_create_edit_reorder_and_unpublish_a_template(): void
    {
        $this->actingAs(User::factory()->create(['is_admin' => true]));
        $payload = $this->payload();
        $this->postJson('/admin/collection-templates', $payload)->assertCreated()->assertJsonPath('template.id', 'equipment');
        $template = CollectionTemplate::where('slug', 'equipment')->firstOrFail();
        $this->getJson('/api/v1/collection-templates')->assertJsonCount(1, 'templates');

        $changedId = $payload;
        $changedId['slug'] = 'new-id';
        $this->postJson('/admin/collection-templates/'.$template->id, $changedId)->assertUnprocessable()->assertJsonValidationErrors('slug');
        $payload['subtitle'] = 'Revised description';
        $payload['sort_order'] = -5;
        $payload['is_active'] = false;
        $payload['schema_json'] = json_encode(['name' => 'Tools', 'fields' => [['label' => 'Tool', 'type' => 'short_text']]]);
        $this->postJson('/admin/collection-templates/'.$template->id, $payload)->assertOk()->assertJsonPath('template.schema.name', 'Tools');
        $this->assertDatabaseHas('collection_templates', ['id' => $template->id, 'subtitle' => 'Revised description', 'sort_order' => -5, 'is_active' => false]);
        $this->getJson('/api/v1/collection-templates')->assertJsonCount(0, 'templates');
        $this->get('/admin/collection-templates')->assertOk()->assertSee('Tools');
    }

    public function test_catalog_management_requires_an_admin(): void
    {
        $template = CollectionTemplate::factory()->create();
        $this->getJson('/admin/collection-templates')->assertUnauthorized();
        $this->postJson('/admin/collection-templates', $this->payload())->assertUnauthorized();
        $this->postJson('/admin/collection-templates/'.$template->id, $this->payload())->assertUnauthorized();
        $this->actingAs(User::factory()->create());
        $this->getJson('/admin/collection-templates')->assertForbidden();
        $this->postJson('/admin/collection-templates', $this->payload())->assertForbidden();
        $this->postJson('/admin/collection-templates/'.$template->id, $this->payload())->assertForbidden();
        $this->assertDatabaseCount('collection_templates', 1);
    }

    #[DataProvider('invalidSchemas')]
    public function test_admin_rejects_invalid_schemas_without_publishing(array $schema, string $path): void
    {
        $this->actingAs(User::factory()->create(['is_admin' => true]));
        $payload = $this->payload();
        $payload['schema_json'] = json_encode($schema);

        $this->postJson('/admin/collection-templates', $payload)->assertUnprocessable()->assertJsonValidationErrors($path);
        $this->assertDatabaseCount('collection_templates', 0);
    }

    public static function invalidSchemas(): array
    {
        $field = ['label' => 'Name', 'type' => 'short_text'];

        return [
            'empty fields' => [['name' => 'Tools', 'fields' => []], 'schema.fields'],
            'blank name' => [['name' => '  ', 'fields' => [$field]], 'schema.name'],
            'unsupported type' => [['name' => 'Tools', 'fields' => [['label' => 'URL', 'type' => 'url']]], 'schema.fields.0.type'],
            'select needs options' => [['name' => 'Tools', 'fields' => [['label' => 'Kind', 'type' => 'single_select']]], 'schema.fields.0.options'],
            'duplicate options' => [['name' => 'Tools', 'fields' => [['label' => 'Kind', 'type' => 'multi_select', 'options' => ['A', 'A']]]], 'schema.fields.0.options'],
            'blank option' => [['name' => 'Tools', 'fields' => [['label' => 'Kind', 'type' => 'single_select', 'options' => [' ']]]], 'schema.fields.0.options.0'],
            'options on text' => [['name' => 'Tools', 'fields' => [$field + ['options' => ['A']]]], 'schema.fields.0.options'],
            'non text primary' => [['name' => 'Tools', 'fields' => [['label' => 'Cost', 'type' => 'number', 'isPrimaryTitle' => true]]], 'schema.fields.0.type'],
            'multiple primary' => [['name' => 'Tools', 'fields' => [$field + ['isPrimaryTitle' => true], $field + ['isPrimaryTitle' => true]]], 'schema.fields'],
            'unknown property' => [['name' => 'Tools', 'fields' => [$field], 'records' => []], 'schema.records'],
            'privacy cannot be supplied' => [['name' => 'Tools', 'fields' => [$field + ['privacy' => ['sync' => true]]]], 'schema.fields.0.privacy'],
            'invalid color' => [['name' => 'Tools', 'fields' => [$field], 'colorHex' => 'red'], 'schema.colorHex'],
            'too many fields' => [['name' => 'Tools', 'fields' => array_fill(0, 51, $field)], 'schema.fields'],
            'string boolean' => [['name' => 'Tools', 'fields' => [$field + ['isRequired' => 'true']]], 'schema.fields.0.isRequired'],
        ];
    }

    public function test_invalid_json_and_duplicate_catalog_ids_return_validation_errors(): void
    {
        $this->actingAs(User::factory()->create(['is_admin' => true]));
        $payload = $this->payload();
        $payload['schema_json'] = '{broken';
        $this->postJson('/admin/collection-templates', $payload)->assertUnprocessable()->assertJsonValidationErrors('schema_json');
        CollectionTemplate::factory()->create(['slug' => 'equipment']);
        $this->postJson('/admin/collection-templates', $this->payload())->assertUnprocessable()->assertJsonValidationErrors('slug');
        $this->assertDatabaseCount('collection_templates', 1);
    }

    public function test_prompt_is_backend_authored_and_contains_the_same_contract_without_calling_ai(): void
    {
        Http::preventStrayRequests();
        $intent = 'Track books and reading notes';
        $response = $this->postJson('/api/v1/collection-prompt', ['intent' => $intent])->assertOk()->assertJsonPath('version', 1)->assertHeader('Cache-Control', 'no-store, private');
        $this->assertStringContainsString($intent, $response->json('prompt'));
        $schema = $this->getJson('/api/v1/collection-schema')->assertOk()->assertJsonPath('x-arca-version', 1)->json();
        $this->assertStringContainsString(json_encode($schema, JSON_UNESCAPED_SLASHES), $response->json('prompt'));
        $this->postJson('/api/v1/collection-prompt', ['intent' => 'Tools', 'records' => ['private']])->assertUnprocessable()->assertJsonValidationErrors('request');
        $this->postJson('/api/v1/collection-prompt', ['intent' => ' '])->assertUnprocessable()->assertJsonValidationErrors('intent');
        $this->postJson('/api/v1/collection-prompt', ['intent' => str_repeat('a', 2001)])->assertUnprocessable()->assertJsonValidationErrors('intent');
    }

    public function test_seeding_is_idempotent_preserves_operator_edits_and_all_templates_validate(): void
    {
        $this->seed(CollectionTemplateSeeder::class);
        $template = CollectionTemplate::where('slug', 'vehicle_maintenance')->firstOrFail();
        $template->update(['subtitle' => 'Operator edit', 'is_active' => false]);
        $this->seed(CollectionTemplateSeeder::class);
        $this->assertDatabaseCount('collection_templates', 3);
        $this->assertDatabaseHas('collection_templates', ['slug' => 'vehicle_maintenance', 'subtitle' => 'Operator edit', 'is_active' => false]);
        foreach (CollectionTemplate::all() as $entry) {
            $this->assertSame($entry->schema_definition, app(CollectionSchemaContract::class)->validate($entry->schema_definition));
        }
    }

    public function test_operator_form_escapes_catalog_text(): void
    {
        CollectionTemplate::factory()->create(['subtitle' => '<script>alert(1)</script>']);
        $this->actingAs(User::factory()->create(['is_admin' => true]))->get('/admin/collection-templates')->assertOk()
            ->assertSee('&lt;script&gt;alert(1)&lt;/script&gt;', false)->assertDontSee('<script>alert(1)</script>', false);
    }

    private function payload(): array
    {
        return [
            'slug' => 'equipment', 'subtitle' => 'Track equipment', 'is_active' => true, 'sort_order' => 0,
            'schema_json' => json_encode(['name' => 'Equipment', 'fields' => [['label' => 'Name', 'type' => 'short_text', 'isPrimaryTitle' => true]]]),
        ];
    }
}
