<?php

namespace App\Filament\Resources;

if (! class_exists(\Filament\Resources\Resource::class)) {
    class AppAnnouncementResource
    {
    }

    return;
}

use App\Models\AppAnnouncement;
use Filament\Forms\Components\DateTimePicker;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class AppAnnouncementResource extends Resource
{
    protected static ?string $model = AppAnnouncement::class;

    protected static string|\BackedEnum|null $navigationIcon = Heroicon::Megaphone;

    protected static ?string $navigationLabel = 'Announcements';

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            TextInput::make('title')
                ->required()
                ->maxLength(255),
            Textarea::make('body')
                ->required()
                ->rows(4),
            TextInput::make('cta_label')
                ->maxLength(100),
            TextInput::make('cta_url')
                ->url()
                ->maxLength(255),
            Select::make('placement')
                ->options([
                    'home_banner' => 'Home Banner',
                    'settings_card' => 'Settings Card',
                    'announcement_modal' => 'Announcement Modal',
                ])
                ->default('home_banner')
                ->required(),
            Select::make('target_platform')
                ->options([
                    'all' => 'All Platforms',
                    'ios' => 'iOS',
                    'android' => 'Android',
                ])
                ->default('all')
                ->required(),
            Select::make('target_tier')
                ->options([
                    'all' => 'All Tiers',
                    'free' => 'Free Only',
                    'pro' => 'Pro Only',
                ])
                ->default('all')
                ->required(),
            Toggle::make('is_active')
                ->default(true),
            TextInput::make('priority')
                ->numeric()
                ->default(0),
            DateTimePicker::make('starts_at'),
            DateTimePicker::make('ends_at'),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('title')->searchable()->sortable(),
                TextColumn::make('placement')->sortable(),
                TextColumn::make('target_platform')->badge(),
                TextColumn::make('target_tier')->badge(),
                IconColumn::make('is_active')->boolean(),
                TextColumn::make('priority')->sortable(),
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
