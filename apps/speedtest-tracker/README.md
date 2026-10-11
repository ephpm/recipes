# Speedtest Tracker on ePHPm

| | |
|---|---|
| App | [Speedtest Tracker](https://speedtest-tracker.dev) v1.15.0 (`SPEEDTEST_TRACKER_VERSION` build arg) — Laravel 13 + Filament 5, PHP ≥ 8.3 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `linuxserver/speedtest-tracker` image (nginx + php-fpm + s6 with its cron and queue runner) |
| Default stack | `compose.yml` — ePHPm + scheduler + queue sidecars, SQLite on a volume (upstream's default); MariaDB/Postgres optional via `DB_*` |
| Single container | the app itself is one container on SQLite; the two sidecars only run `schedule:run` and `queue:work` |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`, SQLite): image build (composer + Vite), migrations + admin seed on start, login through the Filament login form (its Livewire call), dashboard, save Settings → Thresholds through its form and read the value back from the page and the database, Ookla CLI present, `artisan schedule:run` inside the scheduler service. No speedtest was run (needs Ookla servers) |

## What changes versus the linuxserver image

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime; there is no nginx, php-fpm or s6. Laravel's front-controller
  routing comes from `[server] fallback` in `ephpm.toml`.
* **Built from source.** Speedtest Tracker publishes no tarball with
  `vendor/` or built assets, so the image runs `composer install --no-dev`
  (`composer:2` stage) and `npm run build` (Vite, Alpine's `nodejs` on the
  `composer:2` image);
  `artisan package:discover` and `filament:upgrade` then run on the
  embedded PHP.
* **The Ookla Speedtest CLI** (`speedtest`, v1.2.0) is downloaded from
  Ookla exactly as upstream's Dockerfile does and installed in
  `/usr/local/bin`.
* **Same variables as the official image:** `APP_URL`, `APP_TIMEZONE`,
  `DB_CONNECTION`/`DB_*`, `ADMIN_NAME` / `ADMIN_EMAIL` / `ADMIN_PASSWORD`
  (the admin the first migration seeds), `SPEEDTEST_SCHEDULE`,
  `SPEEDTEST_SERVERS`, `PRUNE_RESULTS_OLDER_THAN`, `PUBLIC_DASHBOARD`,
  `MAIL_*`, … — anything from `.env.example` can be set in `environment:`.
* **`APP_KEY` is generated once** into `/data/.env` (`/app/.env` points at
  it, in the `speedtest-data` volume, next to the SQLite database); set
  `APP_KEY` in `environment:` to pin one (the linuxserver image requires
  you to supply it).
* **Scheduler and queue worker are sidecars** from the same image
  (`artisan schedule:run` every minute — which triggers scheduled
  speedtests — and `artisan queue:work`, which runs them). `php` on `PATH`
  is a shim to `ephpm php` so the scheduler's child `php artisan …`
  processes work (`issues/akaunting.md`).
* **Cache and sessions** keep upstream's defaults (`database` cache,
  `cookie` sessions). To use ePHPm's in-process KV store instead, set
  `CACHE_STORE=redis`, `SESSION_DRIVER=redis`, `REDIS_CLIENT=predis`,
  `REDIS_HOST=127.0.0.1`. Not exercised by `test.sh`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Log in with `ADMIN_EMAIL` / `ADMIN_PASSWORD` from `compose.yml` (change the
password before the first start — the migration seeds it — or in the app).
Set `SPEEDTEST_SCHEDULE` (cron syntax) to run tests automatically. `APP_URL`
must be the address users open the app at.

```bash
docker compose exec ephpm speedtest --accept-license --accept-gdpr           # the Ookla CLI by hand
docker compose exec ephpm ephpm php artisan app:ookla-list-servers           # any artisan command
docker compose exec ephpm ephpm kv keys '*'                                  # the live KV store (with the redis drivers above)
docker compose logs ephpm queue                                               # PHP errors, job output
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Fetches the release source and the Ookla CLI, `composer install`s, builds the Vite assets, adds the `php` shim, onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds the volumes and `.env`, generates `APP_KEY`, creates the SQLite file (or waits for MySQL), migrates, starts `ephpm serve` (or runs the given command) |
| `compose.yml` | The stack: ePHPm, scheduler, queue worker |
| `test.sh` | The smoke test CI runs (`bash apps/speedtest-tracker/test.sh`) |

## Configuration notes

* **MariaDB instead of SQLite:** set `DB_CONNECTION=mysql`, `DB_HOST`,
  `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` on all three
  services and add a `db` service; the entrypoint waits for it. ePHPm's
  own embedded database is not an option (the migrations add foreign keys
  with `ALTER TABLE … ADD CONSTRAINT`, see `issues/bookstack.md`).
* Speedtests need outbound internet from the `queue` container (Ookla
  servers); `test.sh` only checks the CLI is installed.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After changing PHP files restart the containers (`ephpm cache reset` is a
  no-op on a single node in v0.11.3 unless `[opcache] cluster_invalidation =
  true` is set — `issues/nextcloud.md`).

## Known limitations

* Results are only as reachable as the Ookla network from your host; the
  Ookla CLI's licence applies.
* Upstream builds on PHP 8.4. On the `-php8.5` image every CLI command
  prints two `Deprecated: Constant PDO::MYSQL_ATTR_SSL_CA is deprecated`
  notices from `config/database.php`; they are harmless (build with
  `EPHPM_TAG=v0.11.3-php8.4` to avoid them).
* Users are added from a modal on the Users page; the smoke test exercises
  a settings form instead, not that modal.
