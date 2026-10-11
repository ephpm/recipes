# Akaunting on ePHPm

| | |
|---|---|
| App | [Akaunting](https://akaunting.com) 3.2.4 (`AKAUNTING_VERSION` build arg) — Laravel 10, PHP ^8.1 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.3` (Akaunting 3.2 is pinned to Laravel 10) |
| Replaces | a nginx/apache + php-fpm host (Akaunting publishes no official image); a Redis service if you ran one |
| Default stack | `compose.yml` — ePHPm + scheduler sidecar + MariaDB 11 |
| Single container | not offered — Akaunting's migrations add foreign keys with `ALTER TABLE … ADD CONSTRAINT`, which ePHPm's embedded database rejects (the failure recorded for BookStack in `issues/bookstack.md`; not re-run here) |
| Status | tested 2026-10-11 on v0.11.3-php8.3 (`compose.yml`): image build, `artisan install` on start, login through the login form, `GET /api/ping` + create a customer (without email — see limitations) and read it back through the REST API with basic auth, `artisan schedule:run` inside the scheduler service |

## What changes versus a classic install

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime. Laravel's front-controller routing comes from `[server] fallback`
  in `ephpm.toml` (the same chain as Akaunting's `nginx.example.com.conf`).
* **The "Stable" release zip is used as-is.** It ships `vendor/` and the
  compiled assets, so there is no Composer or Node stage.
* **Installed by Akaunting's own `artisan install`** on first start — the
  same steps as the web installer at `/install` (writes `.env` with
  `APP_KEY`, migrates, creates the company and the admin user), driven by
  `AKAUNTING_COMPANY_NAME`, `AKAUNTING_COMPANY_EMAIL`,
  `AKAUNTING_ADMIN_EMAIL`, `AKAUNTING_ADMIN_PASSWORD` and `APP_LOCALE`.
  Later starts run `artisan migrate --force` for upgrades.
* **`.env` lives in the `akaunting-storage` volume** (`storage/.env`, with
  `/app/.env` pointing at it): the installer writes `APP_KEY`,
  `APP_INSTALLED` and the database settings there. Values set in
  `environment:` still win over the file.
* **The scheduler is a second container from the same image** running
  `ephpm php artisan schedule:run` every minute — recurring transactions,
  reminders and update checks; upstream asks you to add that cron entry.
* **Cache and sessions** use Laravel's `file` driver by default. To put them
  in ePHPm's in-process KV store instead of running a Redis service, set
  `CACHE_DRIVER=redis`, `SESSION_DRIVER=redis`, `REDIS_CLIENT=predis` and
  `REDIS_HOST=127.0.0.1` (predis ships with Akaunting; the RESP listener is
  enabled in `ephpm.toml`). Not exercised by `test.sh`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Log in with `AKAUNTING_ADMIN_EMAIL` / `AKAUNTING_ADMIN_PASSWORD` from
`compose.yml` (change the password there before the first start, or in the
app afterwards). `APP_URL` must be the address users open Akaunting at
(default `http://localhost:8080`): `APP_URL=https://books.example.com docker compose up -d`.

```bash
curl -u admin@example.com:'Recipe-Pass-9731' http://localhost:8080/api/ping       # the REST API (HTTP basic auth)
docker compose exec ephpm ephpm php artisan update:all                            # any artisan command
docker compose exec ephpm ephpm php artisan schedule:run                          # what the scheduler service runs every minute
docker compose exec ephpm ephpm kv keys '*'                                       # the live KV store (with the redis drivers above)
docker compose logs ephpm                                                          # PHP errors and ePHPm's log
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the Akaunting release zip, copies it onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds the storage volume and `.env`, waits for the DB, runs `artisan install` once (then `migrate`), starts `ephpm serve` (or runs the given command) |
| `compose.yml` | The stack: ePHPm, scheduler, MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/akaunting/test.sh`) |

## Configuration notes

* Uploads up to 64 MiB (`[server.request] max_body_size` + the ini
  overrides); `max_execution_time` is 300 s for app/module installs from
  the UI.
* Apps installed from the Akaunting marketplace are written into
  `/app/modules`, which lives in the image layer, not a volume: they are
  lost when the container is recreated. Mount a volume at `/app/modules` if
  you use them.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After installing apps or changing PHP files run
  `docker compose exec ephpm ephpm cache reset` or restart the container.

## Known limitations

* **Saving a contact with an email address hangs on ePHPm v0.11.3.**
  Akaunting validates emails with Laravel's `email:dns` rule, and PHP's
  `checkdnsrr()` / `dns_get_record()` never return in the ePHPm build
  (`gethostbyname()` works) — the request stalls until the server's request
  timeout. Details and a one-line repro in `issues/akaunting.md`. Until that
  is fixed, leave the email field empty on customers/vendors, or edit
  `app/Http/Requests/Common/Contact.php` to drop the `dns` check.
* **No single-container variant** (see the table above).
* **ePHPm's GD build has no JPEG/WebP/AVIF support** (PNG/GIF/BMP only —
  `issues/koel.md`): JPEG company logos and item pictures cannot be
  resized. `test.sh` uploads no image.
* `imagick` is not available; Akaunting uses GD (`ext-gd`), which is
  present.
