<?php

namespace Database\Factories;

use Illuminate\Database\Eloquent\Factories\Factory;

class CollectionTemplateFactory extends Factory
{
    public function definition(): array
    {
        return [
            'slug' => fake()->unique()->slug(),
            'subtitle' => 'Keep your records organized.',
            'schema_definition' => ['name' => 'Equipment', 'fields' => [
                ['label' => 'Name', 'type' => 'short_text', 'isRequired' => true, 'isPrimaryTitle' => true],
            ]],
            'is_active' => false,
            'sort_order' => 0,
        ];
    }
}
