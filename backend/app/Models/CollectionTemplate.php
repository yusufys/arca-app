<?php

namespace App\Models;

use App\CollectionSchemaContract;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

class CollectionTemplate extends Model
{
    use HasFactory;

    protected $fillable = ['slug', 'subtitle', 'schema_definition', 'localizations', 'is_active', 'sort_order'];

    protected function casts(): array
    {
        return ['schema_definition' => 'array', 'localizations' => 'array', 'is_active' => 'boolean', 'sort_order' => 'integer'];
    }

    protected static function booted(): void
    {
        static::saving(function (CollectionTemplate $template): void {
            app(CollectionSchemaContract::class)->validate($template->schema_definition);
            $template->localizations = self::validateLocalizations($template->localizations ?? []);
        });
    }

    public function catalogEntry(): array
    {
        $entry = ['id' => $this->slug, 'subtitle' => $this->subtitle, 'schema' => $this->schema_definition];
        if (! empty($this->localizations)) {
            $entry['localizations'] = $this->localizations;
        }

        return $entry;
    }

    public static function validateLocalizations(mixed $localizations): array
    {
        $validated = Validator::make(['localizations' => $localizations], [
            'localizations' => ['array:en,tr,ar'],
            'localizations.*' => ['array:subtitle,schema'],
            'localizations.*.subtitle' => ['required', 'string', 'max:500', 'regex:/\\S/u'],
            'localizations.*.schema' => ['required', 'array'],
        ])->validate()['localizations'];
        foreach ($validated as $locale => $entry) {
            try {
                $validated[$locale]['schema'] = app(CollectionSchemaContract::class)->validate($entry['schema']);
            } catch (ValidationException $error) {
                throw ValidationException::withMessages([
                    'localizations.'.$locale.'.schema' => 'The translated schema must satisfy the collection contract.',
                ]);
            }
        }

        return $validated;
    }
}
