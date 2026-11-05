<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // Keep this historical seed snapshot independent of future model and seeder changes.
        $templates = json_decode(<<<'JSON'
[
    {
        "slug": "vehicle_maintenance",
        "subtitle": "Service history, mileage, repairs, and receipts.",
        "is_active": true,
        "sort_order": 0,
        "schema_definition": {
            "name": "Vehicle Maintenance",
            "iconName": "car.fill",
            "colorHex": "#2B5B84",
            "fields": [
                {
                    "label": "Service Summary",
                    "type": "short_text",
                    "isRequired": true,
                    "isPrimaryTitle": true
                },
                {
                    "label": "Service Date",
                    "type": "date",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Odometer",
                    "type": "number",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Category",
                    "type": "single_select",
                    "isRequired": false,
                    "isPrimaryTitle": false,
                    "options": [
                        "Oil & Fluids",
                        "Tires & Brakes",
                        "Inspection",
                        "Repair"
                    ]
                },
                {
                    "label": "Total Cost",
                    "type": "currency",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Shop or Technician",
                    "type": "short_text",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Notes",
                    "type": "long_text",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Invoices & Photos",
                    "type": "attachment",
                    "isRequired": false,
                    "isPrimaryTitle": false
                }
            ]
        }
    },
    {
        "slug": "home_inventory",
        "subtitle": "Valuables, serial numbers, rooms, and replacement values.",
        "is_active": true,
        "sort_order": 1,
        "schema_definition": {
            "name": "Home Inventory",
            "iconName": "house.fill",
            "colorHex": "#3A6B5C",
            "fields": [
                {
                    "label": "Item Name",
                    "type": "short_text",
                    "isRequired": true,
                    "isPrimaryTitle": true
                },
                {
                    "label": "Room",
                    "type": "single_select",
                    "isRequired": false,
                    "isPrimaryTitle": false,
                    "options": [
                        "Living Room",
                        "Kitchen",
                        "Office",
                        "Bedroom",
                        "Garage"
                    ]
                },
                {
                    "label": "Purchase Price",
                    "type": "currency",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Purchase Date",
                    "type": "date",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Serial / Model Number",
                    "type": "short_text",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Condition",
                    "type": "rating",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Receipts & Photos",
                    "type": "attachment",
                    "isRequired": false,
                    "isPrimaryTitle": false
                }
            ]
        }
    },
    {
        "slug": "warranties",
        "subtitle": "Coverage dates, proof of purchase, and support details.",
        "is_active": true,
        "sort_order": 2,
        "schema_definition": {
            "name": "Warranties",
            "iconName": "checkmark.shield.fill",
            "colorHex": "#8C5A2B",
            "fields": [
                {
                    "label": "Product Name",
                    "type": "short_text",
                    "isRequired": true,
                    "isPrimaryTitle": true
                },
                {
                    "label": "Brand / Manufacturer",
                    "type": "short_text",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Purchase Date",
                    "type": "date",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Expiration Date",
                    "type": "date",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Product Cost",
                    "type": "currency",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Active Coverage",
                    "type": "boolean",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Claim Instructions",
                    "type": "long_text",
                    "isRequired": false,
                    "isPrimaryTitle": false
                },
                {
                    "label": "Receipt & Warranty Card",
                    "type": "attachment",
                    "isRequired": false,
                    "isPrimaryTitle": false
                }
            ]
        }
    }
]
JSON, true, 512, JSON_THROW_ON_ERROR);
        foreach ($templates as $template) {
            $template['schema_definition'] = json_encode($template['schema_definition'], JSON_THROW_ON_ERROR);
            $template['created_at'] = now();
            $template['updated_at'] = now();
            DB::table('collection_templates')->insertOrIgnore($template);
        }
    }

    public function down(): void
    {
        // Published suggestions may have operator edits; keep them on rollback.
    }
};
