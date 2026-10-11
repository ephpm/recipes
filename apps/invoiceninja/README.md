# Invoice Ninja (v5) on ePHPm

| | |
|---|---|
| App | [Invoice Ninja](https://invoiceninja.com) v5.13.47 (`NINJA_VERSION` build arg) — Laravel, PHP 8.2–8.5 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `invoiceninja/invoiceninja` (php-fpm) + nginx pair of the official compose file; a Redis service if you ran one |
| Default stack | `compose.yml` — ePHPm + scheduler sidecar + MariaDB 11 |
| Single container | not offered — Invoice Ninja's migrations add foreign keys with `ALTER TABLE … ADD CONSTRAINT`, which ePHPm's embedded database rejects (the failure recorded for BookStack in `issues/bookstack.md`; not re-run here) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, migrations + reference-data seed + first account on start, login through the JSON API, create a client with the returned API token and read it back, `artisan schedule:run` inside the scheduler service |

## What changes versus the official image

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime; there is no nginx container and no php-fpm. Laravel's
  front-controller routing comes from `[server] fallback` in `ephpm.toml`.
* **The release tarball is used as-is.** Invoice Ninja's GitHub release
  ships `vendor/` and the built UI, so the image has no Composer or Node
  stage.
* **First start:** `artisan migrate --force`, then `artisan
  ninja:create-account` with `NINJA_ADMIN_EMAIL` / `NINJA_ADMIN_PASSWORD`
  (what the web signup would create); later starts only migrate.
* **`APP_KEY` is generated once** into `storage/.env` (`/app/.env` points
  at it, in the `ninja-storage` volume) — the `.env.example` placeholder key
  is never used. Set `APP_KEY` in `environment:` to pin one.
* **Same environment variables as Invoice Ninja's `.env`:** `APP_URL`,
  `REQUIRE_HTTPS`, `DB_*`, `MAIL_*`, `PDF_GENERATOR`, `CACHE_DRIVER`,
  `SESSION_DRIVER`, `QUEUE_CONNECTION`, `REDIS_*`, `API_SECRET`, … — every
  key can be set in `environment:` and wins over the `.env` file.
  `REQUIRE_HTTPS=false` is set because Invoice Ninja otherwise redirects
  every request to `https://`.
* **The scheduler is a second container from the same image** running
  `ephpm php artisan schedule:run` every minute (recurring invoices,
  reminders, clean-ups), which Invoice Ninja requires. `php` on `PATH` is a
  shim to `ephpm php` so the scheduler's child `php artisan …` processes
  work (`issues/akaunting.md`).
* **Cache and sessions** use Laravel's `file` driver by default. To put them
  in ePHPm's in-process KV store instead of running a Redis service, set
  `CACHE_DRIVER=redis`, `SESSION_DRIVER=redis`, `REDIS_CLIENT=predis` and
  `REDIS_HOST=127.0.0.1` (predis ships with Invoice Ninja; the RESP
  listener is enabled in `ephpm.toml`). Not exercised by `test.sh`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Log in with `NINJA_ADMIN_EMAIL` / `NINJA_ADMIN_PASSWORD` from `compose.yml`
(change the password there before the first start, or in the app). `APP_URL`
must be the address users open Invoice Ninja at (default
`http://localhost:8080`); behind TLS set it to the `https://` URL and
`REQUIRE_HTTPS=true`.

```bash
docker compose exec ephpm ephpm php artisan ninja:check-data       # any artisan command
docker compose exec ephpm ephpm php artisan schedule:run           # what the scheduler service runs every minute
docker compose exec ephpm ephpm kv keys '*'                        # the live KV store (with the redis drivers above)
docker compose logs ephpm                                           # PHP errors and ePHPm's log
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release tarball, adds the `php` shim, copies the app onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds the volumes and `.env`, generates `APP_KEY`, waits for the DB, migrates, creates the first account, starts `ephpm serve` (or runs the given command) |
| `compose.yml` | The stack: ePHPm, scheduler, MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/invoiceninja/test.sh`) |

## Configuration notes

* Uploads up to 100 MiB (`[server.request] max_body_size` + the ini
  overrides); `max_execution_time` 300 s and a 600 s request ceiling for
  exports/imports; `memory_limit` 512M as upstream recommends.
* **PDFs:** `PDF_GENERATOR=hosted_ninja` (the default in Invoice Ninja's
  `.env.example`) renders PDFs through Invoice Ninja's hosted service. The
  local alternative (`snappdf`) needs a headless Chromium in the image,
  which this recipe does not install.
* **Queue:** `QUEUE_CONNECTION=sync` (upstream's default) runs jobs inline.
  For `database`, add a worker service: `command: ["ephpm", "php",
  "artisan", "queue:work", "--sleep=3", "--tries=3"]`.
* Volumes: `ninja-storage` (`/app/storage`: documents, logs, `.env`) and
  `ninja-public` (`/app/public/storage`: logos). Back them up with the
  database.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After changing PHP files inside a running container run
  `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* **No single-container variant** (see the table above).
* **ePHPm's GD build has no JPEG/WebP/AVIF support** (PNG/GIF/BMP only —
  `issues/koel.md`): JPEG company logos cannot be resized. `test.sh`
  uploads no image.
* No local PDF rendering (see above); `imagick` is not available either
  (Invoice Ninja does not require it).
