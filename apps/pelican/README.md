# Pelican Panel on ePHPm

| | |
|---|---|
| App | [Pelican Panel](https://pelican.dev) v1.0.0-rc.1 (`PELICAN_VERSION` build arg) — Laravel 13 + Filament 5, PHP 8.4/8.5 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `ghcr.io/pelican/panel` image (Caddy + php-fpm + supervisord running the scheduler and the queue worker) |
| Default stack | `compose.yml` — ePHPm + scheduler + queue sidecars, SQLite on a volume (upstream's default); MySQL optional via `DB_*` |
| Single container | the app itself is one container on SQLite; the two sidecars only run `schedule:run` and `queue:work` |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`, SQLite): image build, migrations + admin user on start, login through the Filament login form (its Livewire call), admin dashboard, create an API key through the admin form and see it listed, `artisan schedule:run` inside the scheduler service |

## What changes versus the official image

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime; there is no Caddy, php-fpm or supervisord. Laravel's
  front-controller routing comes from `[server] fallback` in `ephpm.toml`.
* **Built from the release tarball + Composer.** Pelican's `panel.tar.gz`
  ships the built front-end (`public/build`) but not `vendor/`, so the
  image runs `composer install --no-dev` in a `composer:2` stage
  (`--no-scripts`; `artisan package:discover` then runs on the embedded
  PHP). No Node stage.
* **Same persistent layout as the official image:** everything that must
  survive lives under `/pelican-data` (the `pelican-data` volume) — `.env`
  with the generated `APP_KEY`, `database/database.sqlite`, `storage/`
  (avatars, icons, fonts) and `plugins/`; `/app/.env`,
  `database/database.sqlite`, `storage/app/public` and `public/storage`
  are symlinks into it, exactly as upstream's Dockerfile sets up.
* **No web installer.** The entrypoint does what the official entrypoint
  does once `APP_INSTALLED=true` (`artisan migrate --force`) and creates
  the admin the installer would create (`artisan p:user:make` with
  `PELICAN_ADMIN_EMAIL` / `PELICAN_ADMIN_USERNAME` /
  `PELICAN_ADMIN_PASSWORD`).
* **Scheduler and queue worker are sidecars** from the same image
  (`artisan schedule:run` every minute, `artisan queue:work`), replacing
  supervisord's programs. `php` on `PATH` is a shim to `ephpm php` so the
  scheduler's child `php artisan …` processes work (`issues/akaunting.md`).
* **Cache and sessions** use Laravel's `file` driver by default; the queue
  is `database`. To keep cache/sessions in ePHPm's in-process KV store, set
  `CACHE_STORE=redis`, `SESSION_DRIVER=redis`, `REDIS_CLIENT=predis`,
  `REDIS_HOST=127.0.0.1` (predis ships with Pelican). Not exercised by
  `test.sh`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Log in with `PELICAN_ADMIN_EMAIL` / `PELICAN_ADMIN_PASSWORD` from
`compose.yml` (change the password before the first start, or in the
panel). `APP_URL` must be the address users and Wings nodes reach the panel
at: `APP_URL=https://panel.example.com docker compose up -d`.

```bash
docker compose exec ephpm ephpm php artisan p:user:make           # any artisan command
docker compose exec ephpm ephpm php artisan p:node:make
docker compose exec ephpm ephpm kv keys '*'                       # the live KV store (with the redis drivers above)
docker compose logs ephpm                                          # PHP errors and ePHPm's log
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Fetches the release, `composer install`s it, adds the `php` shim and the `/pelican-data` symlinks, onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds `/pelican-data` and `.env`, waits for an external DB when configured, migrates, creates the admin, starts `ephpm serve` (or runs the given command) |
| `compose.yml` | The stack: ePHPm, scheduler, queue worker |
| `test.sh` | The smoke test CI runs (`bash apps/pelican/test.sh`) |

## Configuration notes

* **MySQL/MariaDB instead of SQLite:** set `DB_CONNECTION=mysql`,
  `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` on all
  three services and add a `db` service; the entrypoint waits for it. (ePHPm's
  own embedded database is not an option: Pelican's migrations add foreign
  keys with `ALTER TABLE … ADD CONSTRAINT`, see `issues/bookstack.md`.)
* Uploads up to 100 MiB; `max_execution_time` 300 s and a 600 s request
  ceiling for long panel operations.
* Wings nodes connect to the panel at `APP_URL`; the panel's own TLS is
  best terminated by a proxy in front of ePHPm (or ePHPm's `[server.tls]`).
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After installing plugins or changing PHP files run
  `docker compose exec ephpm ephpm cache reset` or restart the container.

## Known limitations

* **ePHPm's GD build has no JPEG/WebP/AVIF support** (PNG/GIF/BMP only —
  `issues/koel.md`): JPEG avatars/icons cannot be processed. `test.sh`
  uploads no image.
* Pelican is a release candidate upstream (v1.0.0-rc.1).
