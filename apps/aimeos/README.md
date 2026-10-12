# Aimeos on ePHPm

| | |
|---|---|
| App | [Aimeos](https://aimeos.org) shop distribution [`aimeos/aimeos`](https://github.com/aimeos/aimeos) 2026.10.1 (`AIMEOS_VERSION` build arg) — Laravel 13 + `aimeos/aimeos-laravel` |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx/apache + php-fpm (Laravel Sail upstream) and the crontab running `artisan aimeos:jobs` |
| Default stack | `compose.yml` — ePHPm + `jobs` sidecar (same image) + MariaDB 11 |
| Single container | none — not attempted: Aimeos's schema setup goes through Doctrine DBAL's MySQL platform, whose DDL the embedded database rejects (see `issues/shlink.md`) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: migrate + `aimeos:setup` with the demo catalogue + admin account on first start, shop home page, add a product to the basket and read the basket back, admin login through the Breeze form, create a product through the admin GraphQL API and read it back (GraphQL and the JQAdm product list), the `jobs` sidecar runs `aimeos:jobs` (the demo orders' confirmation e-mails, sent to the log mailer) |

## What changes versus a typical install

* **No interactive `composer create-project`.** Upstream's installer asks
  for the database, mail server and admin account on the terminal. Here
  everything comes from the container environment, and `entrypoint.sh` does
  what the installer's post-create scripts do: generates `APP_KEY` once into
  the storage volume, runs `artisan migrate` and `artisan aimeos:setup`
  (with `--option=setup/default/demo:1` on the first start unless
  `AIMEOS_DEMO=0`), and creates/updates the admin from
  `AIMEOS_ADMIN_EMAIL` / `AIMEOS_ADMIN_PASSWORD` with
  `aimeos:account --super --admin`. `aimeos:setup` runs again on every
  start: it is the documented upgrade step and is idempotent.
* **One web process.** ePHPm serves `public/` with the
  `try_files $uri $uri/ /index.php?$query_string` rule as `[server] fallback`.
  The theme/admin assets are published into the image at build time
  (`vendor:publish --tag=public`); the Breeze login/profile pages' Vite bundle
  is built in a `node:22` stage.
* **Cron jobs as a sidecar.** The `jobs` service runs the job list from the
  [Aimeos cron documentation](https://aimeos.org/docs/latest/laravel/setup/#cronjobs)
  (`order/email/*`, `order/service/*`, `order/cleanup/*`,
  `customer/email/watch`, `product/bought`, `index/rebuild`, `index/optimize`)
  through `ephpm php artisan aimeos:jobs ...` every `AIMEOS_JOBS_INTERVAL`
  seconds (default 3600). Upstream suggests several crontab lines with
  different frequencies; adjust the command in `compose.yml` to split them.
  Laravel's scheduler is not used (the distribution's `Console\Kernel`
  schedules nothing), but the image still sets `PHP_BINARY=/usr/local/bin/php`
  (a `php` → `ephpm php` shim) so anything that re-spawns PHP through
  Symfony's `PhpExecutableFinder` works (ephpm#558, `issues/pterodactyl.md`).

## Run

```bash
docker compose up -d                       # or: podman compose up -d
open http://localhost:8080                 # the shop (demo catalogue)
open http://localhost:8080/admin           # admin@example.com / Aimeos-Admin-Pass-1
```

Change the admin credentials (`AIMEOS_ADMIN_EMAIL`, `AIMEOS_ADMIN_PASSWORD`),
`DB_PASSWORD` and `DB_ROOT_PASSWORD` in a `.env` file before the first start.
`APP_URL` must be the URL the shop is opened at (`EPHPM_PORT=8090` →
`APP_URL=http://localhost:8090`); behind a TLS proxy set it and `ASSET_URL`
to the public `https://` URL.

The first start takes a minute or two (`aimeos:setup` creates the shop schema
and the demo data); the web port answers once it is done.

```bash
docker compose exec ephpm ephpm php artisan aimeos:account me@example.com --password=... --editor
docker compose exec ephpm ephpm php artisan aimeos:jobs "index/rebuild"
docker compose exec ephpm ephpm php artisan aimeos:setup --option=setup/default/demo:0   # remove the demo data
docker compose restart ephpm   # after changing PHP code (OPcache does not re-check timestamps)
```

## Environment

Laravel's own variables (`APP_URL`, `APP_KEY`, `DB_*`, `MAIL_*`,
`SESSION_DRIVER`, `CACHE_DRIVER`, `QUEUE_CONNECTION`, …) and the
distribution's `SHOP_*` switches (`SHOP_MULTILOCALE`, `SHOP_MULTISHOP`,
`SHOP_REGISTRATION`, `SHOP_PERMISSION`) are read from the environment as in
`.env.example`; there is no `.env` file in the container. Recipe-specific:

| Variable | Default | |
|---|---|---|
| `AIMEOS_ADMIN_EMAIL` / `AIMEOS_ADMIN_PASSWORD` | `admin@example.com` / `Aimeos-Admin-Pass-1` | super-user created/updated at every start |
| `AIMEOS_DEMO` | `1` | `0` skips the demo catalogue on the first setup |
| `AIMEOS_JOBS_INTERVAL` | `3600` | seconds between `aimeos:jobs` runs in the `jobs` service |

Volumes: `storage` (`/app/storage`: `APP_KEY`, logs, sessions, file cache)
and `media` (`/app/public/aimeos`: uploaded product images and files).

## Known limitations

* ePHPm's GD has no JPEG/WebP/AVIF support (known ePHPm limit). Aimeos
  scales uploaded images into previews, so uploading JPEG/WebP product images
  in the admin is expected to fail; PNG/GIF should work. Not exercised by the
  smoke test.
* Cache and sessions default to the `file` driver in the storage volume.
  Laravel's `redis` driver could point at ePHPm's built-in KV
  (`REDIS_HOST=127.0.0.1`, listener enabled in `ephpm.toml`), but the
  distribution ships no `predis/predis` and ePHPm has no `redis` extension;
  not set up here.
