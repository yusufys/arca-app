<?php

namespace App\Filament\Resources;

if (! class_exists(\Filament\Resources\Resource::class)) {
    class EnrolledDeviceResource
    {
    }

    return;
}

use App\Models\EnrolledDevice;
use Filament\Forms\Components\DateTimePicker;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class EnrolledDeviceResource extends Resource
{
    protected static ?string $model = EnrolledDevice::class;

    protected static string|\BackedEnum|null $navigationIcon = Heroicon::DevicePhoneMobile;

    protected static ?string $navigationLabel = 'Enrolled Devices';

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            TextInput::make('device_name')
                ->required()
                ->maxLength(255),
            Select::make('platform')
                ->options([
                    'ios' => 'iOS',
                    'android' => 'Android',
                    'macos' => 'macOS',
                ])
                ->required(),
            TextInput::make('public_key_x25519')
                ->required(),
            DateTimePicker::make('last_synced_at'),
            DateTimePicker::make('revoked_at'),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('id')->searchable(),
                TextColumn::make('user.email')->label('User')->searchable(),
                TextColumn::make('device_name')->searchable(),
                TextColumn::make('platform')->badge(),
                TextColumn::make('last_synced_at')->dateTime()->sortable(),
                TextColumn::make('revoked_at')->dateTime()->sortable(),
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
