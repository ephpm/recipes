# FreeScout on ePHPm

| | |
|---|---|
| App | [FreeScout](https://freescout.net) 1.8.247 (`FREESCOUT_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache/nginx + php-fpm + the `* * * * * php artisan schedule:run` crontab entry (which also keeps FreeScout's queue worker alive) |
| Default stack | `compose.yml` — ePHPm + scheduler + queue worker (same image) + MariaDB 11 |
| Single container | none — not attempted |
| Status | tested 2026-10-11 on v0.11.3-php8.5: migrations + admin user on first start, login, create a mailbox and read it back, the scheduler runs scheduled commands (fetch-emails, monitors) through the embedded PHP, queue worker running, `.env` 403 |

FreeScout has no official Docker image; this replaces the web server +
PHP-FPM + cron setup from its installation guide.

## What changes versus a stock install

* **One web process.** ePHPm serves `public/` (the root `.htaccess` only
  rewrites into it); `public/.htaccess`'s front-controller rule is
  `[server] fallback`.
* **No web installer step.** On the first start the entrypoint generates
  `APP_KEY` into `storage/.env` (the `storage` volume; `/app/.env` links to
  it), runs `freescout:after-app-update` (config cache + migrations) and
  creates the first admin with `freescout:create-user`
  (`FREESCOUT_ADMIN_EMAIL` / `FREESCOUT_ADMIN_PASSWORD`). Everything else —
  `APP_URL`, `DB_*`, `APP_TIMEZONE`, `APP_FORCE_HTTPS`, mail settings —
  comes from the container environment.
* **Scheduler and queue worker are sidecars.** Upstream's single crontab
  entry runs `schedule:run`, which also starts `queue:work` in the
  background. Here `scheduler` runs `schedule:run --no-interaction` every
  minute (FreeScout then skips launching its own worker) and `queue` runs
  `queue:work` on the same queues FreeScout would
  (`emails,default,<md5 of APP_KEY>`).
* **The scheduler runs commands with the right PHP.** Laravel builds every
  scheduled command as `<PHP_BINARY> artisan ...`, and `PHP_BINARY` is
  `ephpm` under `ephpm php` (ephpm#558), so out of the box every scheduled
  command (mail fetching included) would fail silently as
  `ephpm artisan ...`. FreeScout's bundled Symfony Process ignores the
  `PHP_BINARY` environment variable, so the Dockerfile patches FreeScout's
  own `overrides/.../Console/Application.php` to take the binary from
  `LARAVEL_PHP_BINARY` (set to the `php` → `ephpm php` shim).
* **OPcache checks timestamps** (`opcache_validate_timestamps = true`, every
  2 s): FreeScout updates itself and installs modules from the web UI and
  rewrites its cached config when settings change.
* `procps` is installed: FreeScout's scheduler uses `ps` to watch its queue
  workers.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 APP_URL=http://localhost:8090 ... to change
```

Log in with `FREESCOUT_ADMIN_EMAIL` / `FREESCOUT_ADMIN_PASSWORD`
(`admin@example.com` / `FreeScout-Admin-Pass-1` — set your own in a `.env`
file before the first start), then add a mailbox and its IMAP/SMTP settings
in the UI.

```bash
docker compose exec ephpm php artisan freescout:clear-cache
docker compose exec ephpm php artisan freescout:fetch-emails
docker compose exec ephpm php artisan freescout:create-user
docker compose logs -f scheduler queue
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | The release tag (vendor committed upstream), `procps`, the scheduler PHP-binary patch, onto `ephpm/ephpm` |
| `ephpm.toml` | Server config: `public/` root, front controller, 40 MiB attachments, OPcache timestamp checks |
| `entrypoint.sh` | `APP_KEY`, wait for the DB, `after-app-update`, first admin, `ephpm serve`; `scheduler` / `queue` modes |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/freescout/test.sh`) |

## Configuration notes

* Behind a TLS-terminating proxy set `APP_FORCE_HTTPS=true`, an `https://`
  `APP_URL`, and `[server.security] trusted_proxies`.
* Mail fetching uses FreeScout's bundled pure-PHP IMAP client (no `imap`
  extension needed — ePHPm does not have it).
* Modules installed from the UI go into `Modules/` and `public/modules/` in
  the container, not a volume: they survive restarts but not a container
  re-creation. Bake modules you depend on into the image.

## Known limitations

* FreeScout is a Laravel 5.5 application. It runs on PHP 8.5 here, but the
  CLI may print deprecation notices from old dependencies.
* GD in ePHPm has no JPEG/WebP/FreeType: avatar and image-attachment
  thumbnails in JPEG are not generated.
