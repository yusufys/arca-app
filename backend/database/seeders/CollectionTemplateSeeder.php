<?php

namespace Database\Seeders;

use App\Models\CollectionTemplate;
use Illuminate\Database\Seeder;

class CollectionTemplateSeeder extends Seeder
{
    public function run(): void
    {
        $localizations = json_decode(file_get_contents(resource_path('contracts/starter-localizations.json')), true, 512, JSON_THROW_ON_ERROR);
        $templates = [
            ['vehicle_maintenance', 'Vehicle Maintenance', 'Service history, mileage, repairs, and receipts.', 'car.fill', '#2B5B84', [
                ['Service Summary', 'short_text'], ['Service Date', 'date'], ['Odometer', 'number'],
                ['Category', 'single_select', ['Oil & Fluids', 'Tires & Brakes', 'Inspection', 'Repair']],
                ['Total Cost', 'currency'], ['Shop or Technician', 'short_text'], ['Notes', 'long_text'], ['Invoices & Photos', 'attachment'],
            ]],
            ['home_inventory', 'Home Inventory', 'Valuables, serial numbers, rooms, and replacement values.', 'house.fill', '#3A6B5C', [
                ['Item Name', 'short_text'], ['Room', 'single_select', ['Living Room', 'Kitchen', 'Office', 'Bedroom', 'Garage']],
                ['Purchase Price', 'currency'], ['Purchase Date', 'date'], ['Serial / Model Number', 'short_text'],
                ['Condition', 'rating'], ['Receipts & Photos', 'attachment'],
            ]],
            ['warranties', 'Warranties', 'Coverage dates, proof of purchase, and support details.', 'checkmark.shield.fill', '#8C5A2B', [
                ['Product Name', 'short_text'], ['Brand / Manufacturer', 'short_text'], ['Purchase Date', 'date'],
                ['Expiration Date', 'date'], ['Product Cost', 'currency'], ['Active Coverage', 'boolean'],
                ['Claim Instructions', 'long_text'], ['Receipt & Warranty Card', 'attachment'],
            ]],
        ];
        foreach ($templates as $index => [$slug, $name, $subtitle, $icon, $color, $fields]) {
            CollectionTemplate::firstOrCreate(['slug' => $slug], [
                'subtitle' => $subtitle,
                'localizations' => $localizations[$slug],
                'is_active' => true,
                'sort_order' => $index,
                'schema_definition' => [
                    'name' => $name, 'iconName' => $icon, 'colorHex' => $color,
                    'fields' => array_map(function (array $field, int $position): array {
                        $result = ['label' => $field[0], 'type' => $field[1], 'isRequired' => $position === 0, 'isPrimaryTitle' => $position === 0];
                        if (isset($field[2])) {
                            $result['options'] = $field[2];
                        }

                        return $result;
                    }, $fields, array_keys($fields)),
                ],
            ]);
        }
    }
}
