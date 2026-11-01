<?php

namespace App\Filament\Resources;

if (! class_exists(\Filament\Resources\Resource::class)) {
    class PublicRecordSnapshotResource
    {
    }

    return;
}

use App\Models\PublicRecordSnapshot;
use Filament\Forms\Components\DateTimePicker;
use Filament\Forms\Components\TextInput;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class PublicRecordSnapshotResource extends Resource
{
    protected static ?string $model = PublicRecordSnapshot::class;

    protected static string|\BackedEnum|null $navigationIcon = Heroicon::Share;

    protected static ?string $navigationLabel = 'Public Snapshots';

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            TextInput::make('space_id')
                ->required()
                ->uuid(),
            TextInput::make('record_id')
                ->required()
                ->uuid(),
            TextInput::make('share_token')
                ->required()
                ->maxLength(64),
            DateTimePicker::make('expires_at'),
            DateTimePicker::make('revoked_at'),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('id')->searchable(),
                TextColumn::make('user.email')->label('User')->searchable(),
                TextColumn::make('share_token')->searchable(),
                TextColumn::make('space_id')->limit(12),
                TextColumn::make('record_id')->limit(12),
                TextColumn::make('revoked_at')->dateTime()->sortable(),
                TextColumn::make('expires_at')->dateTime()->sortable(),
                TextColumn::make('created_at')->dateTime()->sortable(),
            ]);
    }

    public static function getRelations(): array
    {
        return [];
    }

    public static function getPages(): array
    {
        return [];
    }
}
