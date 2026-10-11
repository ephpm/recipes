# Laravel on ePHPm

| | |
|---|---|
| App | [Laravel](https://laravel.com) 12 application skeleton (`laravel/laravel`, `LARAVEL_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm, Redis (cache + sessions), Octane's Swoole/RoadRunner server |
| Default stack | `compose.yml` — ePHPm (per-request mode) + MariaDB 11 |
| Worker mode | `compose.worker.yml` — ePHPm persistent workers via the native Octane driver + MariaDB |
| Single container | `compose.embedded.yml` — ePHPm with its embedded database + KV (**experimental**) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (all three variants): `/up` 200, welcome page, migrations, session cookie stored in the KV store, Eloquent insert via `artisan tinker` read back over HTTP (per-request/embedded) or via tinker (worker) |

This recipe builds the stock skeleton so it is testable on its own. For
your application replace the `composer create-project` line in the
`Dockerfile` with `COPY . /app` + `composer install`, keep the rest.

## What changes versus nginx + php-fpm

* **One process.** `[server] fallback` in `ephpm.toml` is the
  `try_files $uri $uri/ /index.php?$query_string` rule; `document_root` is
  `public/`.
* **Cache and sessions without Redis.** `ephpm.toml` enables ePHPm's
  loopback RESP listener (`127.0.0.1:6379`), and the compose files set
  `CACHE_STORE=redis`, `SESSION_DRIVER=redis`, `REDIS_CLIENT=predis`
  (`predis/predis` is added in the image). Laravel speaks Redis to the
  in-process KV store. Inspect it with `docker compose exec ephpm ephpm kv keys '*'`.
  Queues stay on `QUEUE_CONNECTION=database`; a Redis *queue* should stay a
  real Redis service.
* **Artisan runs on the embedded PHP.** `docker compose exec ephpm ephpm php artisan ...`.
* **`APP_KEY`** comes from the environment, or is generated once into the
  `storage` volume (`storage/.app_key`) on first start.
* **Migrations run at start** (`entrypoint.sh`); set `SKIP_MIGRATE=1` to opt out.

## Run

```bash
docker compose up -d                 # per-request mode + MariaDB
docker compose exec ephpm ephpm php artisan about
```

### Worker mode (Octane driver)

```bash
docker compose -f compose.worker.yml up -d
```

`ephpm.worker.toml` sets `[php] mode = "worker"` with
`[php.worker] script = "vendor/bin/ephpm-octane-worker"` — the
[`ephpm/octane-driver`](https://github.com/ephpm/octane-driver) package
(installed from its GitHub repo together with `laravel/octane`). The
application boots once per worker thread and loops over requests; ePHPm
supervises the workers, so `php artisan octane:start` is never used. Note
that `document_root` is the project root in this mode (the worker script
must live under it) and that every non-static request is handled by the
booted application — stray PHP files in `public/` are not executed.
Octane's worker-mode hygiene rules apply to your code. See the
[Laravel Octane guide](https://ephpm.dev/guides/laravel-octane/).

### Single container, embedded database (experimental)

```bash
docker compose -f compose.embedded.yml up -d
```

No MariaDB: `ephpm.embedded.toml` adds `[db.sqlite]` and ePHPm serves the
MySQL wire protocol on `127.0.0.1:3306` from its embedded SQLite-compatible
engine (Turso, Beta upstream). Laravel keeps `DB_CONNECTION=mysql` and the
stock `pdo_mysql` driver. Migrations run in the background once the server
is up (the embedded database only accepts connections after startup). The
database file lives in the `ephpm-data` volume.

## Environment

The usual Laravel variables (`APP_URL`, `APP_KEY`, `DB_*`, `CACHE_STORE`,
`SESSION_DRIVER`, `REDIS_*`, `QUEUE_CONNECTION`, `LOG_CHANNEL`, …). The image
sets production defaults (`APP_ENV=production`, `APP_DEBUG=false`,
`LOG_CHANNEL=stderr`). There is no `.env` file in the image; everything is
read from the container environment (`getenv()` / `$_ENV`, which ePHPm
passes through).

| Variable | Default | Purpose |
|---|---|---|
| `EPHPM_CONFIG` | `/etc/ephpm/ephpm.toml` | Which ePHPm config to serve with (`ephpm.worker.toml`, `ephpm.embedded.toml`) |
| `EPHPM_APP_BASE` | `/app` | Project root for the Octane worker |
| `SKIP_MIGRATE` | `0` | Set `1` to skip `artisan migrate` at start |

## Queue worker and scheduler

Run them on the same image (see the commented `queue` service in
`compose.yml`):

```yaml
  queue:
    image: recipes-laravel
    command: ephpm php artisan queue:work --sleep=3 --tries=3
  scheduler:
    image: recipes-laravel
    command: sh -c 'while true; do ephpm php artisan schedule:run; sleep 60; done'
```

## Configuration notes

* After deploying new code, run `docker compose exec ephpm ephpm cache reset`
  or restart: ePHPm's `serve` mode keeps OPcache timestamp validation off.
* `[php] max_execution_time = 60` is enforced per request on Linux;
  `[server.timeouts] request` (default 300 s) is the outer backstop.
* The three `[server.security]` sandbox flags are set to `false` explicitly
  because they only act in ePHPm's multi-tenant mode.
* Behind a TLS-terminating proxy, set `[server.security] trusted_proxies` and
  Laravel's `TrustProxies` middleware as usual.

## Known limitations

* The embedded-database variant is experimental (Turso is Beta upstream);
  MySQL-specific SQL in migrations or queries may fail there.
* Octane features not yet implemented by the ePHPm driver: `Octane::table()`,
  `Octane::tick()`, `Octane::concurrently()`, `--watch`.
* Worker mode is a whole-server switch; it cannot be combined with ePHPm's
  multi-tenant `sites_dir` mode.
