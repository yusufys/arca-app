<?php

namespace App\Models;

use App\CollectionSchemaContract;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class CollectionTemplate extends Model
{
    use HasFactory;

    protected $fillable = ['slug', 'subtitle', 'schema_definition', 'is_active', 'sort_order'];

    protected function casts(): array
    {
        return ['schema_definition' => 'array', 'is_active' => 'boolean', 'sort_order' => 'integer'];
    }

    protected static function booted(): void
    {
        static::saving(function (CollectionTemplate $template): void {
            app(CollectionSchemaContract::class)->validate($template->schema_definition);
        });
    }

    public function catalogEntry(): array
    {
        return ['id' => $this->slug, 'subtitle' => $this->subtitle, 'schema' => $this->schema_definition];
    }
}
