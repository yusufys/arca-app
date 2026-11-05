<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $entries = json_decode(<<<'JSON'
{
  "vehicle_maintenance": {
    "base": {
      "subtitle": "Service history, mileage, repairs, and receipts.",
      "schema": {
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
    "localizations": {
      "tr": {
        "subtitle": "Servis geçmişi, kilometre, onarım ve faturalar.",
        "schema": {
          "name": "Araç Bakımı",
          "iconName": "car.fill",
          "colorHex": "#2B5B84",
          "fields": [
            {
              "label": "Servis Özeti",
              "type": "short_text",
              "isRequired": true,
              "isPrimaryTitle": true
            },
            {
              "label": "Servis Tarihi",
              "type": "date",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Kilometre Sayacı",
              "type": "number",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Kategori",
              "type": "single_select",
              "isRequired": false,
              "isPrimaryTitle": false,
              "options": [
                "Yağ ve Sıvılar",
                "Lastikler ve Frenler",
                "Muayene",
                "Onarım"
              ]
            },
            {
              "label": "Toplam Tutar",
              "type": "currency",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Servis veya Usta",
              "type": "short_text",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Notlar",
              "type": "long_text",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Faturalar ve Fotoğraflar",
              "type": "attachment",
              "isRequired": false,
              "isPrimaryTitle": false
            }
          ]
        }
      },
      "ar": {
        "subtitle": "سجل الصيانة والمسافة المقطوعة والإصلاحات والفواتير.",
        "schema": {
          "name": "صيانة المركبة",
          "iconName": "car.fill",
          "colorHex": "#2B5B84",
          "fields": [
            {
              "label": "ملخّص الصيانة",
              "type": "short_text",
              "isRequired": true,
              "isPrimaryTitle": true
            },
            {
              "label": "تاريخ الصيانة",
              "type": "date",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "عداد المسافة",
              "type": "number",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "الفئة",
              "type": "single_select",
              "isRequired": false,
              "isPrimaryTitle": false,
              "options": [
                "الزيوت والسوائل",
                "الإطارات والمكابح",
                "الفحص",
                "الإصلاح"
              ]
            },
            {
              "label": "التكلفة الإجمالية",
              "type": "currency",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "الورشة أو الفني",
              "type": "short_text",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "ملاحظات",
              "type": "long_text",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "الفواتير والصور",
              "type": "attachment",
              "isRequired": false,
              "isPrimaryTitle": false
            }
          ]
        }
      }
    }
  },
  "home_inventory": {
    "base": {
      "subtitle": "Valuables, serial numbers, rooms, and replacement values.",
      "schema": {
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
    "localizations": {
      "tr": {
        "subtitle": "Değerli eşyalar, seri numaraları, odalar ve yenileme bedelleri.",
        "schema": {
          "name": "Ev Envanteri",
          "iconName": "house.fill",
          "colorHex": "#3A6B5C",
          "fields": [
            {
              "label": "Eşya Adı",
              "type": "short_text",
              "isRequired": true,
              "isPrimaryTitle": true
            },
            {
              "label": "Oda",
              "type": "single_select",
              "isRequired": false,
              "isPrimaryTitle": false,
              "options": [
                "Oturma Odası",
                "Mutfak",
                "Çalışma Odası",
                "Yatak Odası",
                "Garaj"
              ]
            },
            {
              "label": "Satın Alma Fiyatı",
              "type": "currency",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Satın Alma Tarihi",
              "type": "date",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Seri / Model Numarası",
              "type": "short_text",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Durum",
              "type": "rating",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Makbuzlar ve Fotoğraflar",
              "type": "attachment",
              "isRequired": false,
              "isPrimaryTitle": false
            }
          ]
        }
      },
      "ar": {
        "subtitle": "المقتنيات والأرقام التسلسلية والغرف وتكاليف الاستبدال.",
        "schema": {
          "name": "مقتنيات المنزل",
          "iconName": "house.fill",
          "colorHex": "#3A6B5C",
          "fields": [
            {
              "label": "اسم المقتنى",
              "type": "short_text",
              "isRequired": true,
              "isPrimaryTitle": true
            },
            {
              "label": "الغرفة",
              "type": "single_select",
              "isRequired": false,
              "isPrimaryTitle": false,
              "options": [
                "غرفة المعيشة",
                "المطبخ",
                "المكتب",
                "غرفة النوم",
                "المرآب"
              ]
            },
            {
              "label": "سعر الشراء",
              "type": "currency",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "تاريخ الشراء",
              "type": "date",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "الرقم التسلسلي أو رقم الطراز",
              "type": "short_text",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "الحالة",
              "type": "rating",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "الإيصالات والصور",
              "type": "attachment",
              "isRequired": false,
              "isPrimaryTitle": false
            }
          ]
        }
      }
    }
  },
  "warranties": {
    "base": {
      "subtitle": "Coverage dates, proof of purchase, and support details.",
      "schema": {
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
    },
    "localizations": {
      "tr": {
        "subtitle": "Garanti tarihleri, satın alma belgeleri ve destek bilgileri.",
        "schema": {
          "name": "Garantiler",
          "iconName": "checkmark.shield.fill",
          "colorHex": "#8C5A2B",
          "fields": [
            {
              "label": "Ürün Adı",
              "type": "short_text",
              "isRequired": true,
              "isPrimaryTitle": true
            },
            {
              "label": "Marka / Üretici",
              "type": "short_text",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Satın Alma Tarihi",
              "type": "date",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Bitiş Tarihi",
              "type": "date",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Ürün Tutarı",
              "type": "currency",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Aktif Garanti",
              "type": "boolean",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Başvuru Talimatları",
              "type": "long_text",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "Makbuz ve Garanti Belgesi",
              "type": "attachment",
              "isRequired": false,
              "isPrimaryTitle": false
            }
          ]
        }
      },
      "ar": {
        "subtitle": "تواريخ التغطية وإثبات الشراء وتفاصيل الدعم.",
        "schema": {
          "name": "الضمانات",
          "iconName": "checkmark.shield.fill",
          "colorHex": "#8C5A2B",
          "fields": [
            {
              "label": "اسم المنتج",
              "type": "short_text",
              "isRequired": true,
              "isPrimaryTitle": true
            },
            {
              "label": "العلامة التجارية أو المصنّع",
              "type": "short_text",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "تاريخ الشراء",
              "type": "date",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "تاريخ الانتهاء",
              "type": "date",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "تكلفة المنتج",
              "type": "currency",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "تغطية سارية",
              "type": "boolean",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "تعليمات المطالبة بالضمان",
              "type": "long_text",
              "isRequired": false,
              "isPrimaryTitle": false
            },
            {
              "label": "الإيصال وبطاقة الضمان",
              "type": "attachment",
              "isRequired": false,
              "isPrimaryTitle": false
            }
          ]
        }
      }
    }
  }
}
JSON, true, 512, JSON_THROW_ON_ERROR);
        foreach ($entries as $slug => $entry) {
            $row = DB::table('collection_templates')->where('slug', $slug)->first();
            if ($row && $row->localizations === null
                && json_decode($row->schema_definition, true) == $entry['base']['schema']
                && $row->subtitle === $entry['base']['subtitle']) {
                DB::table('collection_templates')->where('id', $row->id)->update([
                    'localizations' => json_encode($entry['localizations'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
                ]);
            }
        }
    }

    public function down(): void
    {
        // Preserve administrator edits and translated content on rollback.
    }
};
