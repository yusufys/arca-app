<?php

namespace App\Filament\Resources;

if (! class_exists(\Filament\Resources\Resource::class)) {
    class UserResource
    {
    }

    return;
}

use App\Models\User;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class UserResource extends Resource
{
    protected static ?string $model = User::class;

    protected static string|\BackedEnum|null $navigationIcon = Heroicon::Users;

    protected static ?string $navigationLabel = 'Users';

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            TextInput::make('name')
                ->required()
                ->maxLength(255),
            TextInput::make('email')
                ->email()
                ->required()
                ->maxLength(255),
            Select::make('subscription_tier')
                ->options([
                    'free' => 'Free',
                    'pro' => 'Pro',
                ])
                ->default('free')
                ->required(),
            Select::make('subscription_state')
                ->options([
                    'active' => 'Active',
                    'billing_grace_period' => 'Billing Grace Period',
                    'expired' => 'Expired',
                    'revoked_or_refunded' => 'Revoked or Refunded',
                ])
                ->default('active')
                ->required(),
            TextInput::make('remote_storage_bytes_used')
                ->numeric()
                ->default(0),
            Toggle::make('is_admin')
                ->default(false),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('id')->sortable(),
                TextColumn::make('name')->searchable(),
                TextColumn::make('email')->searchable(),
                TextColumn::make('subscription_tier')->badge(),
                TextColumn::make('subscription_state')->badge(),
                TextColumn::make('remote_storage_bytes_used')->numeric()->sortable(),
                IconColumn::make('is_admin')->boolean(),
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
