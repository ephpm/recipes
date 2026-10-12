# Lychee on ePHPm

| | |
|---|---|
| App | [Lychee](https://lycheeorg.dev) v7.10.0 (`LYCHEE_VERSION` build arg) — Laravel 12 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `lycheeorg/lychee` image (FrankenPHP / Octane) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not offered |
| Status | **blocked** — ePHPm's GD has no WebP (or JPEG) support (`issues/koel.md`): Lychee writes every size variant (thumbnails, small, medium) as WebP, so an upload stores the original but generates no thumbnail (`Call to undefined function imagewebp()` in `GdHandler::save`); JPEG originals cannot be decoded at all. Checked 2026-10-11 on v0.11.3-php8.5: image build, migrations, admin creation, login, create/list an album and the PNG upload itself work; `test.sh` fails at the thumbnail check |

## What the recipe does

* **One process.** ePHPm serves `public/` with the Laravel front-controller
  fallback, in per-request mode (the official image runs FrankenPHP's
  Octane worker; Lychee's Octane setup is FrankenPHP-specific).
* **Built from the release zip** (`Lychee.zip`, with `vendor/` and the built
  front end) — no Composer or Node stage.
* **First start:** `APP_KEY` is generated into `storage/.env` (the `storage`
  volume; `/app/.env` links to it), `php artisan migrate --force` runs on
  every start, and with `LYCHEE_ADMIN_PASSWORD` set the administrator is
  created with `php artisan lychee:create_user … --may-administrate`
  (otherwise Lychee asks for one in the browser).
* `ENV PHP_BINARY=/usr/local/bin/php` plus a `php` → `ephpm php` shim, so
  anything Laravel re-spawns finds a working PHP (`issues/pterodactyl.md`).
  No scheduler/queue service is included (`QUEUE_CONNECTION=sync`).

## Environment

Lychee's own variables (`.env.example`): `APP_URL`, `APP_ENV`,
`DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`,
`DB_PASSWORD`, `TIMEZONE`, `TRUSTED_PROXIES`, `MAIL_*`, … — set them in
`environment:`. Recipe-specific: `LYCHEE_ADMIN_USER` (default `admin`) and
`LYCHEE_ADMIN_PASSWORD` (first start only).

## Run

```bash
LYCHEE_ADMIN_PASSWORD='something-long' docker compose up -d
open http://localhost:8080        # EPHPM_PORT=8090 ... — then APP_URL=http://localhost:8090
docker compose exec ephpm php artisan lychee:diagnostics
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Release zip onto `ephpm/ephpm`, `php` shim, `PHP_BINARY` |
| `ephpm.toml` | Server config (`public/` root, front-controller fallback, 100 MiB uploads) |
| `entrypoint.sh` | Seeds volumes and `.env`, `APP_KEY`, waits for the DB, migrates, creates the admin, starts `ephpm serve` |
| `compose.yml` | ePHPm + MariaDB |
| `test.sh` | Smoke test: login, album, PNG upload, thumbnail (fails today, see Status) |

## What would unblock it

GD built with `libwebp` and `libjpeg` in the php-sdk (`issues/koel.md`), or
`ext-imagick` (Lychee prefers Imagick when it is loaded). Lychee has no
option to shell out to an external ImageMagick, so the `convert` approach
used by `apps/piwigo` does not apply.
