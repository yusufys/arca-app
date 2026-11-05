# Arca collection catalog

The public endpoints are `GET /api/v1/collection-templates`, `GET /api/v1/collection-schema`, and `POST /api/v1/collection-prompt` with `{ "intent": "Describe a collection" }`. They require no cloud account. The prompt endpoint returns copyable instructions; it does not call an AI service. The collection intent is limited to 2,000 characters and is not stored by this feature. The app should send a collection idea, never existing records.

After releasing the backend code, run `php artisan migrate --force`. The catalog-only data migration inserts the three initial suggestions, preserving any matching IDs. To restore missing initial suggestions later, run `php artisan db:seed --class=CollectionTemplateSeeder --force`. Re-running the seeder leaves existing catalog entries and operator edits intact. The database seeder also invokes this seeder on fresh installations.

An administrator opens `/admin`, then **Manage suggested collections**. Create a draft with a unique stable catalog ID (the ID cannot change after creation), description, sort order, and collection JSON. Save the draft to validate it. Set its status to Active to publish it; set it back to Draft to withdraw it. Lower sort order appears first, with stable catalog ID as the tie-breaker. Editing or withdrawing a suggestion does not alter collections users already created.

`resources/contracts/collection-v1.json` is the authoritative version 1 JSON Schema used for backend validation, public schema responses, and AI prompt instructions. The iOS app bundles a byte-identical resource for offline validation. Keep both copies identical when editing the contract; the Swift parity test detects drift. Version 1 supports only the field types in the contract, one optional short-text primary title, and nonblank unique string options for select fields. IDs, record values, privacy configuration, and unknown keys are not accepted. Changes that invalidate existing version 1 documents require a new contract version.

Run catalog tests with `php artisan test --compact tests/Feature/CollectionCatalogTest.php`.

<p align="center"><a href="https://laravel.com" target="_blank"><img src="https://raw.githubusercontent.com/laravel/art/master/logo-lockup/5%20SVG/2%20CMYK/1%20Full%20Color/laravel-logolockup-cmyk-red.svg" width="400" alt="Laravel Logo"></a></p>

<p align="center">
<a href="https://github.com/laravel/framework/actions"><img src="https://github.com/laravel/framework/workflows/tests/badge.svg" alt="Build Status"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/dt/laravel/framework" alt="Total Downloads"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/v/laravel/framework" alt="Latest Stable Version"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/l/laravel/framework" alt="License"></a>
</p>

## About Laravel

Laravel is a web application framework with expressive, elegant syntax. We believe development must be an enjoyable and creative experience to be truly fulfilling. Laravel takes the pain out of development by easing common tasks used in many web projects, such as:

- [Simple, fast routing engine](https://laravel.com/docs/routing).
- [Powerful dependency injection container](https://laravel.com/docs/container).
- Multiple back-ends for [session](https://laravel.com/docs/session) and [cache](https://laravel.com/docs/cache) storage.
- Expressive, intuitive [database ORM](https://laravel.com/docs/eloquent).
- Database agnostic [schema migrations](https://laravel.com/docs/migrations).
- [Robust background job processing](https://laravel.com/docs/queues).
- [Real-time event broadcasting](https://laravel.com/docs/broadcasting).

Laravel is accessible, powerful, and provides tools required for large, robust applications.

## Learning Laravel

Laravel has the most extensive and thorough [documentation](https://laravel.com/docs) and video tutorial library of all modern web application frameworks, making it a breeze to get started with the framework.

In addition, [Laracasts](https://laracasts.com) contains thousands of video tutorials on a range of topics including Laravel, modern PHP, unit testing, and JavaScript. Boost your skills by digging into our comprehensive video library.

You can also watch bite-sized lessons with real-world projects on [Laravel Learn](https://laravel.com/learn), where you will be guided through building a Laravel application from scratch while learning PHP fundamentals.

## Agentic Development

Laravel's predictable structure and conventions make it ideal for AI coding agents like Claude Code, Cursor, and GitHub Copilot. Install [Laravel Boost](https://laravel.com/docs/ai) to supercharge your AI workflow:

```bash
composer require laravel/boost --dev

php artisan boost:install
```

Boost provides your agent 15+ tools and skills that help agents build Laravel applications while following best practices.

## Contributing

Thank you for considering contributing to the Laravel framework! The contribution guide can be found in the [Laravel documentation](https://laravel.com/docs/contributions).

## Code of Conduct

In order to ensure that the Laravel community is welcoming to all, please review and abide by the [Code of Conduct](https://laravel.com/docs/contributions#code-of-conduct).

## Security Vulnerabilities

If you discover a security vulnerability within Laravel, please send an e-mail to Taylor Otwell via [taylor@laravel.com](mailto:taylor@laravel.com). All security vulnerabilities will be promptly addressed.

## License

The Laravel framework is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).
