# Bagisto on ePHPm

| | |
|---|---|
| App | [Bagisto](https://bagisto.com) v2.5.0 (`BAGISTO_VERSION` build arg) — Laravel 13 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | a nginx/apache + php-fpm host and the cron entry for the Laravel scheduler (Bagisto has no official production image) |
| Default stack | `compose.yml` — ePHPm + the scheduler (same image) + MariaDB 11 |
| Single container | not offered — Bagisto supports MySQL/MariaDB only and its Laravel migrations add foreign keys with `ALTER TABLE … ADD CONSTRAINT`, which the embedded database rejects (see [issues/bookstack.md](../../issues/bookstack.md)); not attempted |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, unattended `bagisto:install` on first start with the admin account taken from `BAGISTO_ADMIN_*`, shop home page, customer sign-up through the registration form, admin login through the login form, the new customer read back from the admin customer grid, `artisan migrate:status` on the embedded PHP |

## What changes versus a classic install

* **One process serves the shop.** ePHPm is the HTTP server and the PHP
  runtime; `public/.htaccess` (everything that is not a file goes to
  `index.php`) is `[server] fallback` in `ephpm.toml`.
* **Built from the release tag.** The image runs `composer install --no-dev`
  in a `composer:2` stage (`--no-scripts`; `artisan package:discover` then
  runs on the embedded PHP). The theme bundles are committed upstream in
  `public/themes/*/build`, so there is no Node stage.
* **Unattended install on first start.** The entrypoint runs Bagisto's own
  `artisan bagisto:install --no-interaction` (APP_KEY, schema, seed data —
  locale, currency, the default channel and the admin account — and the
  `storage/installed` marker the web installer also writes), then sets the
  admin's e-mail/password from `BAGISTO_ADMIN_EMAIL` /
  `BAGISTO_ADMIN_PASSWORD` when given. Later starts run
  `artisan migrate --force`. The installer starts with `db:wipe`, so the
  entrypoint never runs it against a database that already holds a Bagisto
  schema (it just writes the marker back if the storage volume was lost).
* **Two installer quirks handled in the entrypoint:** the installer reloads
  its settings from the `.env` *file* rather than the process environment,
  so the container's `APP_*`/`DB_*` variables are copied into
  `storage/.env`; and it runs with `APP_ENV=local`, because in production
  Laravel refuses its `db:wipe` / `migrate:fresh` under `--no-interaction`
  (the file is switched back to `APP_ENV` afterwards).
* **`.env` lives in the storage volume** (`/app/.env` points at it), so the
  generated `APP_KEY` survives container recreation. Every variable set in
  `compose.yml` still wins over the file.
* **Scheduler as a service.** `scheduler` runs `artisan schedule:run` every
  60 seconds (the cron line Bagisto's docs ask for) on the same image; the
  `php` shim in the image lets scheduled `->command()` entries spawn
  `php artisan …` (see `issues/akaunting.md`).

## Run

```bash
BAGISTO_ADMIN_EMAIL=you@example.com BAGISTO_ADMIN_PASSWORD=change-me docker compose up -d
open http://localhost:8080          # the shop
open http://localhost:8080/admin    # the admin panel
```

Without `BAGISTO_ADMIN_*` the installer's default `admin@example.com` /
`admin123` is kept; change it. `APP_URL` must be the URL customers open
(default `http://localhost:8080`; with `EPHPM_PORT` set it to match): image
and asset URLs are built from it. The first start takes a minute or two
(schema + seed data); the log says `Bagisto is ready` when it is done.

```bash
docker compose exec ephpm ephpm php artisan migrate:status   # any artisan command
docker compose exec ephpm ephpm php artisan indexer:index
docker compose logs ephpm                                     # Laravel logs to stderr here
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Fetches the release source, `composer install`s it, copies it onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, blocked paths, upload limits, timeouts) |
| `entrypoint.sh` | Seeds the storage volume and `.env`, waits for the DB, installs or migrates, starts `ephpm serve` (or the given command once installed) |
| `compose.yml` | ePHPm + scheduler + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/bagisto/test.sh`) |

## Configuration notes

* `storage` volume: product/category images (`storage/app/public`, served
  through the `public/storage` symlink), logs, `.env`, the installed
  marker. PHP is never executed from `/storage/` (`blocked_paths`).
* Cache and sessions use the database (Bagisto's `.env.example` default).
  ePHPm's RESP listener is enabled on `127.0.0.1:6379`; Bagisto bundles
  `predis`, so `CACHE_STORE=redis`, `SESSION_DRIVER=redis`,
  `REDIS_CLIENT=predis`, `REDIS_HOST=127.0.0.1` should put them in the
  in-process KV store instead. Not exercised by `test.sh`.
* `QUEUE_CONNECTION` stays `sync` (the `.env.example` default). For a
  queued setup add a worker service running
  `ephpm php artisan queue:work` with `QUEUE_CONNECTION=database` (or a
  real Redis broker).
* Mail goes to the log (`MAIL_MAILER=log`) until you configure SMTP.
* Behind a TLS-terminating proxy set `APP_URL` to the public `https://`
  URL and `[server.security] trusted_proxies` in `ephpm.toml`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After installing an extension package run
  `docker compose exec ephpm ephpm cache reset` or restart the container.

## Known limitations

* **ePHPm's GD build has no JPEG/WebP/FreeType support** (PNG/GIF/BMP only —
  `issues/koel.md`). Bagisto resizes product and category images with
  intervention/image on GD, so JPEG/WebP product images cannot be
  processed; PNG and GIF uploads should work. `test.sh` uploads no image
  and does not seed the demo catalogue (`--demo-samples`), which ships
  JPEG/WebP images.
* Elasticsearch-backed search, payment gateways, and checkout were not
  exercised; the smoke test covers install, customer sign-up, admin login
  and the admin customer grid.
* `checkdnsrr()` / `dns_get_record()` hang in ePHPm v0.11.3
  ([issues/freshrss.md](../../issues/freshrss.md)); a validation rule that
  checks e-mail domains over DNS would hang its request.
