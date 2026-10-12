# Filament Demo on ePHPm

| | |
|---|---|
| App | [Filament Demo](https://github.com/filamentphp/demo) (Laravel 12 + Filament 5), branch `5.x` at `866461e` (`DEMO_COMMIT` build arg; the repo has no release tags) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm (or `php artisan serve` / Octane) and the cron entry for `artisan schedule:run` |
| Default stack | `compose.yml` — ePHPm + scheduler sidecar (same image) + PostgreSQL 17 (what the hosted demo runs on; its hourly reset is PostgreSQL-only) |
| Single container | none |
| Status | **blocked** — ePHPm's GD has no JPEG support: the demo seeder attaches JPEG images to every product and Spatie Media Library's `thumb` conversion fails (`imagecreatefromstring(): No JPEG support in this PHP build`), so `db:seed` aborts and there is no admin user or demo data. Checked 2026-10-11 on v0.11.3-php8.5: image builds, migrations run on PostgreSQL, the scheduler lists `app:reset-demo-database`; `test.sh` has not passed |

## What the recipe does

* `entrypoint.sh` does what upstream's `composer setup` does: generates
  `APP_KEY` once into the storage volume, runs `artisan migrate`, and seeds
  the demo data (`db:seed`) when the `users` table is empty
  (`DEMO_SEED=0` skips it). Upstream's login is
  `admin@filamentphp.com` / `demo.Filament@2021!` (from the seeder).
* ePHPm serves `public/` with the `try_files $uri $uri/
  /index.php?$query_string` rule as `[server] fallback`; the panel theme is
  built with Vite in a `node:22` stage; `public/storage` links to the
  `public` disk in the storage volume (product images, uploads).
* The `scheduler` service runs `ephpm php artisan schedule:run` every
  minute. The demo schedules one task: `app:reset-demo-database` hourly
  (rebuilds the data in a fresh PostgreSQL schema and swaps it in, as the
  hosted demo does). Drop the service to keep changes. The image sets
  `PHP_BINARY=/usr/local/bin/php` (a `php` → `ephpm php` shim) because the
  scheduler spawns `<PHP binary> artisan ...` (ephpm#558,
  `issues/pterodactyl.md`).
* `APP_ENV` defaults to `local`: with `production` the demo forces
  `https://` URLs (`AppServiceProvider`), which is right only behind a TLS
  proxy.

## Run

```bash
docker compose up -d     # blocked on v0.11.3: the seed step fails (see Status)
docker compose exec ephpm ephpm php artisan make:filament-user   # an admin without the demo data
```

## Known limitations

* **Blocked:** see Status. Product images in this demo are JPEG-only
  (`acceptsMimeTypes(['image/jpeg'])`), so even with an empty database
  uploading a product image fails the same way. Unblocked when ePHPm's PHP
  SDK builds GD with libjpeg (known ePHPm limit, `issues/koel.md`).
