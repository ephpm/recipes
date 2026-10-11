# Snipe-IT on ePHPm

| | |
|---|---|
| App | [Snipe-IT](https://snipeitapp.com) v8.8.0 (`SNIPEIT_VERSION` build arg) — Laravel 12, PHP ≥ 8.2 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `snipe/snipe-it` image (Apache + PHP); a Redis service if you ran one for cache/sessions |
| Default stack | `compose.yml` — ePHPm + scheduler sidecar + MariaDB 11 |
| Single container | not offered — Snipe-IT's migrations add foreign keys with `ALTER TABLE … ADD CONSTRAINT`, which ePHPm's embedded database rejects (the failure recorded for BookStack in `issues/bookstack.md`; not re-run here) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, migrations on start, web setup wizard (pre-flight, migrate, admin account), login through the login form, create a manufacturer through the web form and read its page back, `artisan schedule:run` inside the scheduler service |

## What changes versus the official image

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime; there is no Apache. Laravel's front-controller routing comes from
  `[server] fallback` in `ephpm.toml` (the same thing `public/.htaccess`
  does under Apache).
* **Built from the release tag.** Snipe-IT publishes no tarball with
  `vendor/`, so the image runs `composer install --no-dev` in a
  `composer:2` stage (`--no-scripts`; `artisan package:discover` and the
  Livewire asset publish then run on the embedded PHP). The JS/CSS bundles
  are committed upstream (`public/js/build`, `public/css/build`), so there
  is no Node stage.
* **Same environment variables as the official image's `.env.docker`:**
  `APP_URL`, `APP_KEY`, `DB_CONNECTION`, `DB_HOST`, `DB_PORT`,
  `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `MAIL_*`, `APP_TRUSTED_PROXIES`,
  `CACHE_DRIVER`, `SESSION_DRIVER`, `REDIS_*`, `IMAGE_LIB`, … — every key can
  be set in `environment:` and wins over the `.env` file. The official
  entrypoint's `*_FILE` secret indirection is **not** implemented.
* **`APP_KEY` is generated once** by the entrypoint into `storage/.env`
  (`/app/.env` points at it, in the `snipeit-storage` volume) — the
  official image refuses to start without one you generated yourself. Set
  `APP_KEY` in `environment:` to pin it.
* **Migrations run on start** (`artisan migrate --force`), as the official
  startup script does; Passport's migrations are copied into
  `database/migrations` at build time the same way. The web setup wizard
  then does the rest: pre-flight, `migrate` (creates the Passport keys) and
  the first admin.
* **The scheduler is a second container from the same image** running
  `ephpm php artisan schedule:run` every minute (expiring-asset and
  licence alerts, backups, LDAP sync). Upstream asks you to add that cron
  entry yourself; the official image has none.
* **Cache and sessions** use Laravel's `file` driver by default. To put them
  in ePHPm's in-process KV store instead of running a Redis service, set
  `CACHE_DRIVER=redis`, `SESSION_DRIVER=redis` and `REDIS_HOST=127.0.0.1`
  (predis ships with Snipe-IT; the RESP listener is enabled in
  `ephpm.toml`). Not exercised by `test.sh`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

The setup wizard appears on first visit. `APP_URL` must be the address you
open Snipe-IT at (default `http://localhost:8080`): the pre-flight page
compares it with the request URL, and every link is built from it —
`APP_URL=https://assets.example.com docker compose up -d`. The pre-flight
shows two rows in red that are expected here: "the files are owned by
root" (everything in the container runs as root, as in the official image)
and, when the container cannot reach `APP_URL` from inside, the
`.env`-exposure self-check (ePHPm denies dot-files, so `/.env` is 403 —
confirm in your browser as the page suggests).

```bash
docker compose exec ephpm ephpm php artisan snipeit:backup      # any artisan command
docker compose exec ephpm ephpm php artisan schedule:run        # what the scheduler service runs every minute
docker compose exec ephpm ephpm kv keys '*'                     # the live KV store (with the redis drivers above)
docker compose logs ephpm                                        # PHP errors and ePHPm's log
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Fetches the release source, `composer install`s it, publishes the Livewire assets, copies Passport's migrations, onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `env.template` | Seed for `storage/.env` (official variable names) |
| `entrypoint.sh` | Seeds the volumes and `.env`, generates `APP_KEY`, waits for the DB, migrates, starts `ephpm serve` (or runs the given command) |
| `compose.yml` | The stack: ePHPm, scheduler, MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/snipe-it/test.sh`) |

## Configuration notes

* Uploads/imports: `[server.request] max_body_size` and the ini overrides
  are 100 MiB; `max_header_size` is raised to 16 KiB like the official
  image's Apache `LimitRequestFieldSize` (large cookies, SAML responses).
* Behind a TLS-terminating proxy set `APP_TRUSTED_PROXIES` (Snipe-IT's own
  list) and `APP_URL` to the public URL.
* Volumes: `snipeit-storage` (`/app/storage`: private uploads, backups,
  Passport keys, logs, `.env`) and `snipeit-uploads` (`/app/public/uploads`:
  logos, avatars, asset images). Back them up with the database. Backups
  made from the admin UI use `mysqldump`, which is **not** in the image
  (`DB_DUMP_PATH`); run `docker compose exec db mariadb-dump …` instead.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After changing PHP files inside a running container run
  `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* **No single-container variant** (see the table above).
* `ext-ldap` is not in the ePHPm build (Snipe-IT lists it under
  `suggest`): LDAP/AD login and sync are not available; SAML and local
  accounts are unaffected (SAML untested here).
* **ePHPm's GD build has no JPEG/WebP/AVIF support** (PNG/GIF/BMP only —
  `issues/koel.md`). `IMAGE_LIB=gd` resizes uploaded images, so JPEG/WebP
  logos and asset photos cannot be processed; PNG works. `test.sh` uploads
  no image.
* The admin-UI backup/restore feature needs `mysqldump`/`mysql` binaries,
  which this image does not ship.
