# Shlink on ePHPm

| | |
|---|---|
| App | [Shlink](https://shlink.io) 5.1.7 (`SHLINK_VERSION` build arg; `SHLINK_PHP` picks the dist zip's PHP minor) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the official `shlinkio/shlink` image (RoadRunner + its own HTTP server), or nginx/apache + php-fpm from the "classic web server" docs |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | `compose.sqlite.yml` — Shlink's own SQLite file (supported upstream). ePHPm's embedded database is not available: Doctrine's MySQL DDL fails on it ([issues/shlink.md](../../issues/shlink.md)) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml` and `compose.sqlite.yml`): schema + initial API key created by the entrypoint, short URL created through the REST API, its redirect followed (302), the visit counted, the URL listed through the API and the `shlink` CLI |

## What changes versus the official image

* **Per-request PHP instead of RoadRunner.** `shlinkio/shlink` runs
  `bin/roadrunner-worker.php` as a persistent worker behind RoadRunner's
  HTTP server (one booted application per worker, kept across requests).
  This recipe serves `public/index.php` in ePHPm's per-request mode — the
  deployment shape Shlink's own
  [classic web server](https://shlink.io/documentation/classic-web-server/)
  page describes for nginx/apache + php-fpm, with ePHPm as the one process.
  Each request bootstraps the application (Shlink's Mezzio container is
  cheap; the config cache in `data/cache` is still used), so per-request
  latency is higher than under RoadRunner, and the features that depend on a
  long-lived process are off: no RoadRunner job queue, so
  **visit geolocation, webhooks/Matomo tracking and the "real-time updates"
  publishing run inline with the redirect** instead of in background jobs.
  ePHPm's worker mode is not used (Shlink has no ePHPm/PSR-15 worker adapter
  tested here).
* **Same environment variables as `shlinkio/shlink`**
  ([full list](https://shlink.io/documentation/environment-variables/)):
  `DEFAULT_DOMAIN`, `IS_HTTPS_ENABLED`, `DB_DRIVER`, `DB_HOST`, `DB_NAME`,
  `DB_USER`, `DB_PASSWORD`, `DB_PORT`, `INITIAL_API_KEY`, `GEOLITE_LICENSE_KEY`,
  `SKIP_INITIAL_GEOLITE_DOWNLOAD`, `BASE_PATH`, `TIMEZONE`, the `REDIS_*`,
  `RABBITMQ_*`, `MATOMO_*` and `*_FILE` variants. Shlink reads them itself.
* **Release dist, no build.** The image downloads
  `shlink<version>_php<minor>_dist.zip` (vendor included) into `/etc/shlink`,
  the official image's path. `shlink` on `PATH` runs `bin/cli` on the
  embedded PHP, as in the official image.
* **The installer is replaced by its own steps.** `shlink-installer init`,
  `shlink db:create` and `shlink db:migrate` spawn Doctrine as a PHP
  sub-process through `PHP_BINARY`, which under `ephpm php` is the `ephpm`
  executable and cannot run a script — see
  [issues/shlink.md](../../issues/shlink.md). `entrypoint.sh` runs the same
  Doctrine commands directly (`orm:schema-tool:create` on an empty database,
  `migrations:migrate`, `orm:generate-proxies`, `orm:clear-cache:metadata`,
  `api-key:initial`). Everything else in `shlink` (`short-url:*`, `api-key:*`,
  `visit:*`, `domain:*`, `tag:*`) works.

## Run

```bash
INITIAL_API_KEY=change-me docker compose up -d           # or: podman compose
curl -H 'X-Api-Key: change-me' http://localhost:8080/rest/v3/short-urls
```

`DEFAULT_DOMAIN` (default `localhost:8080`) is the domain short URLs are
generated for; set it and `IS_HTTPS_ENABLED=true` for a real deployment.
Then:

```bash
docker compose exec ephpm shlink api-key:generate
docker compose exec ephpm shlink short-url:create https://example.com
docker compose exec ephpm shlink short-url:list
```

Manage it from a browser with [shlink-web-client](https://app.shlink.io)
pointed at your instance and API key.

### Single container, Shlink's SQLite (supported)

```bash
INITIAL_API_KEY=change-me docker compose -f compose.sqlite.yml up -d
```

No database server: Shlink keeps `data/database.sqlite` in the `data`
volume. This is Shlink's own small-install option.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release dist onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds `data/`, waits for the DB, creates/migrates the schema, creates the initial API key, starts `ephpm serve` |
| `shlink` | `bin/cli` wrapper over the embedded PHP |
| `compose.yml`, `compose.sqlite.yml` | The two stacks |
| `test.sh` | The smoke test CI runs (`bash apps/shlink/test.sh`) |

## Configuration notes

* `data/` (cache, locks, logs, ORM proxies, GeoLite DB, SQLite file) is a
  volume. `/etc/shlink/public` only holds `index.php` and `favicon.ico`, so
  nothing else is reachable over HTTP.
* Caching: without `REDIS_SERVERS` Shlink uses APCu when loaded, else the
  filesystem. APCu is not loaded here (it is in ePHPm's extension catalog
  if you want it). `REDIS_SERVERS=tcp://127.0.0.1:6379` would point Shlink's
  Symfony cache at ePHPm's RESP listener, but Shlink's Redis use also covers
  locks (`symfony/lock` with Lua scripts) and pub/sub, which the listener
  does not implement — leave it unset, or run a real Redis.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and `IS_HTTPS_ENABLED=true`; Shlink's own `TRUSTED_PROXIES` is for its
  IP-address middleware.
* `[server.timeouts]` and `[php] max_execution_time = 60` are enough for
  the API; raise them if you import large lists with `short-url:import`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After an image upgrade the container restarts anyway; after in-place edits
  run `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* No RoadRunner, so no background job queue: tracking work runs inline
  (see above). Visit counts, geolocation lookups and webhooks still happen,
  just on the request's own thread.
* `shlink-installer`, `shlink db:create` and `shlink db:migrate` do not work
  in the container (`PHP_BINARY` sub-process spawning —
  [issues/shlink.md](../../issues/shlink.md)); the entrypoint covers both
  install and upgrade migrations on every start.
* `pdo_sqlsrv` (Microsoft SQL Server) is not in the ePHPm build; use
  MariaDB/MySQL, PostgreSQL or SQLite.
