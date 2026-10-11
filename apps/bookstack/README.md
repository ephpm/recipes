# BookStack on ePHPm

| | |
|---|---|
| App | [BookStack](https://www.bookstackapp.com) v26.09.1 (`BOOKSTACK_VERSION` build arg) — Laravel 12 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `linuxserver/bookstack` image (nginx + php-fpm + s6-overlay) and a Redis service for cache/sessions |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not offered — BookStack's migrations add foreign keys with `ALTER TABLE … ADD CONSTRAINT`, which the embedded database rejects (see `issues/bookstack.md`) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, migrations on start, login as the seeded admin, create a book through the web form and read it back, `artisan migrate:status` on the embedded PHP |

## What changes versus the linuxserver image

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime; there is no nginx, no php-fpm and no s6 service tree. Laravel's
  front-controller routing comes from `[server] fallback` in `ephpm.toml`.
* **Built from the release tag.** BookStack publishes no tarball with
  `vendor/`, so the image runs `composer install --no-dev` in a
  `composer:2` stage (`--no-scripts`; `artisan package:discover` then runs on
  the embedded PHP). The JS/CSS bundles are committed upstream in
  `public/dist`, so there is no Node stage.
* **Same environment variables as BookStack's `.env`.** `APP_URL`, `DB_HOST`,
  `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `CACHE_DRIVER`,
  `SESSION_DRIVER`, `REDIS_SERVERS`, `MAIL_*`, `AUTH_METHOD`, `STORAGE_TYPE`,
  … — every key from `.env.example.complete` can be set in `environment:`
  and wins over the `.env` file.
* **`APP_KEY` is generated once** by the entrypoint into `storage/.env`
  (`/app/.env` points at it, in the `bookstack-storage` volume). The
  linuxserver image refuses to start without an `APP_KEY` you generated
  yourself; set `APP_KEY` in `environment:` to pin one.
* **Migrations run on start** (`ephpm php artisan migrate --force`), exactly
  as the linuxserver init does: a fresh database gets the schema and the
  default `admin@admin.com` / `password` account; an existing one is
  upgraded.
* **Cache and sessions** use Laravel's `file` driver by default. To put them
  in ePHPm's in-process KV store instead of running a Redis service, set
  `CACHE_DRIVER=redis`, `SESSION_DRIVER=redis` and
  `REDIS_SERVERS=127.0.0.1:6379:0` (BookStack's redis client is predis, which
  it bundles; the RESP listener is enabled in `ephpm.toml`). Not exercised by
  `test.sh`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Log in as `admin@admin.com` / `password` and change both. `APP_URL` must be
the address users open BookStack at (default `http://localhost:8080`;
behind a proxy the public `https://` URL): every link, redirect and asset
URL is built from it. `APP_URL=https://wiki.example.com docker compose up -d`.

```bash
docker compose exec ephpm ephpm php artisan bookstack:cleanup-images   # any artisan command
docker compose exec ephpm ephpm php artisan migrate:status
docker compose exec ephpm ephpm kv keys '*'                            # the live KV store (with the redis drivers above)
docker compose logs ephpm                                               # PHP errors and ePHPm's log
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Fetches the release source, `composer install`s it, copies it onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds the volumes and `.env`, generates `APP_KEY`, waits for the DB, migrates, starts `ephpm serve` (or runs the given command) |
| `compose.yml` | The stack: ePHPm + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/bookstack/test.sh`) |

## Configuration notes

* Uploads: `[server.request] max_body_size` and the `upload_max_filesize` /
  `post_max_size` ini overrides are 100 MiB (the linuxserver default);
  BookStack's own `FILE_UPLOAD_SIZE_LIMIT` (50 MB) applies on top.
* `memory_limit` is 512M (BookStack's dev image raises it for PDF exports).
  PDF export uses the bundled dompdf; `wkhtmltopdf` is not installed.
* Behind a TLS-terminating proxy set `APP_PROXIES` (BookStack's own
  trusted-proxy list) and `APP_URL` to the public URL; optionally
  `[server.security] trusted_proxies` in `ephpm.toml` for ePHPm's logs and
  rate limits.
* Volumes: `bookstack-storage` (`/app/storage`: attachments, logs, `.env`)
  and `bookstack-uploads` (`/app/public/uploads`: images). Themes live in
  `/app/themes` inside the image; mount a directory there to customise.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After changing PHP files (themes with PHP hooks, for instance) run
  `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* **No single-container variant.** BookStack's `2015_08_29_105422_add_roles_and_permissions`
  migration (and many later ones) adds foreign keys with
  `ALTER TABLE … ADD CONSTRAINT … FOREIGN KEY`, which SQLite/Turso has no
  equivalent for; ePHPm's embedded database fails there. Details in
  `issues/bookstack.md`.
* `ext-ldap` is not in the ePHPm build, so `AUTH_METHOD=ldap` is not
  available. SAML2, OpenID Connect and the social logins are pure PHP and
  unaffected (untested here).
* **ePHPm's GD build has no JPEG/WebP/AVIF support** (PNG/GIF/BMP only —
  `issues/koel.md`). BookStack resizes uploaded images with
  intervention/image on the GD driver, so JPEG and WebP uploads cannot be
  thumbnailed; PNG and GIF work. `test.sh` uploads no image.
