# wallabag on ePHPm

| | |
|---|---|
| App | [wallabag](https://wallabag.org) 2.6.14 (`WALLABAG_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.4` (the official image ships PHP 8.4; wallabag 2.6 is not tested upstream on 8.5) |
| Replaces | the official `wallabag/wallabag` image (nginx + php-fpm supervised by s6) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | `compose.sqlite.yml` — wallabag's own SQLite file (the official default). ePHPm's embedded database is not shipped: Doctrine's MySQL DDL fails on it ([issues/shlink.md](../../issues/shlink.md)) |
| Status | tested 2026-10-11 on v0.11.3-php8.4 (`compose.yml` and `compose.sqlite.yml`): `wallabag:install` run by the entrypoint, login through the form, quickstart page, an article saved through the new-entry form and listed, `wallabag:user:list` on the console |

## What changes versus the official image

* **One process.** ePHPm serves `web/` and runs PHP; the official image's
  nginx `try_files $uri /app.php$is_args$args` becomes `[server] fallback`
  in `ephpm.toml`.
* **Same environment variables as `wallabag/wallabag`.** `entrypoint.sh`
  writes `app/config/parameters.yml` from the `SYMFONY__ENV__*` variables
  (`DATABASE_DRIVER`, `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`,
  `DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_CHARSET`,
  `DATABASE_TABLE_PREFIX`, `DOMAIN_NAME`, `SERVER_NAME`, `SECRET`,
  `MAILER_DSN`, `FROM_EMAIL`, `TWOFACTOR_SENDER`, `LOCALE`,
  `FOSUSER_REGISTRATION`, `FOSUSER_CONFIRMATION`, `REDIS_*`, `RABBITMQ_*`,
  `SENTRY_DSN`) with the official image's defaults.
* **Two differences:** `SYMFONY__ENV__SECRET` is optional — when unset a
  secret is generated once and kept in the `data` volume
  (`data/ephpm-secret`) instead of the official image's fixed, public
  default; and the MySQL/PostgreSQL database is expected to exist (your
  compose creates it), so `MYSQL_ROOT_PASSWORD` / `POSTGRES_*` are not used.
* **Release tarball, no build.** The image downloads
  `wallabag-<version>.tar.gz` (vendor and compiled assets included); the
  official image re-runs `composer install` on every start, this one does not.
* **`wallabag:install` runs on first start** (schema, migrations, the default
  admin `wallabag` / `wallabag`, exactly as the official image), and
  `doctrine:migrations:migrate` on later starts.
* **The console runs on the embedded PHP:**
  `docker compose exec ephpm wallabag wallabag:import:redis-worker ...`
  (`wallabag` wraps `ephpm php bin/console --env=prod`).

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # wallabag / wallabag — change it under Config
```

`SYMFONY__ENV__DOMAIN_NAME` must be the URL users actually open
(`EPHPM_PORT=8090 SYMFONY__ENV__DOMAIN_NAME=http://localhost:8090 …`).

```bash
docker compose exec ephpm wallabag wallabag:user:list
docker compose exec ephpm wallabag fos:user:create alice alice@example.com secret
docker compose exec ephpm wallabag wallabag:import alice ~/pocket.json
```

### Single container, wallabag's SQLite (supported)

```bash
docker compose -f compose.sqlite.yml up -d
```

No database server: `data/db/wallabag.sqlite` in the `data` volume, the
official image's default.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release tarball onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Writes `parameters.yml`, waits for the DB, installs/migrates, warms the cache, starts `ephpm serve` |
| `wallabag` | `bin/console --env=prod` wrapper over the embedded PHP |
| `compose.yml`, `compose.sqlite.yml` | The two stacks |
| `test.sh` | The smoke test CI runs (`bash apps/wallabag/test.sh`) |

## Configuration notes

* `data/` (SQLite file, generated secret, import assets) and
  `web/assets/images` (article pictures) are volumes.
* `[server.security] blocked_paths` 404s `/app.php*` and `/app_dev.php*`
  (the official nginx marks the front controller `internal`), and PHP under
  the upload directories.
* Uploads/imports: `[server.request] max_body_size` is 100 MiB (the official
  nginx `client_max_body_size`) with matching ini overrides.
  `[server.timeouts] request = 300` matches `fastcgi_read_timeout 300s`.
* `error_reporting` excludes `E_DEPRECATED`: wallabag 2.6 on PHP 8.4 logs a
  deprecation on nearly every request otherwise (the official image's
  production `php.ini` does the same).
* Sessions use Symfony's native file handler in `var/sessions` (the app's
  `handler_id: session.handler.native_file`). To keep them in ePHPm's KV
  store instead, set `handler_id: null` in `app/config/config.yml` and
  `["session.save_handler", "ephpm"]` in `[php] ini_overrides` — not done
  here, since it changes a file inside the release.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and an `https://` `SYMFONY__ENV__DOMAIN_NAME`.
* Async imports (`wallabag:import:redis-worker` / RabbitMQ) need a real
  Redis or RabbitMQ: the Redis worker uses list commands (`LPUSH`/`BRPOP`),
  which ePHPm's RESP listener does not implement. Imports through the web UI
  run synchronously and need nothing.
* OPcache runs with timestamp validation off (ePHPm's `serve` default); the
  Symfony cache is rebuilt by the entrypoint on every start.

## Known limitations

* `ext-tidy` (listed in wallabag's `composer.json`) is not in the ePHPm
  build. It is optional at runtime: graby only runs HTML through tidy when the
  extension exists, so article extraction works without it, with slightly
  less clean-up of malformed pages.
* `imagick` is not available; image handling uses GD (compiled in).
* The console wrapper disables session cookies (`session.use_cookies=0`)
  because `ephpm php` reports `headers_sent()` as true from the start, which
  made `wallabag:install`'s admin step and `fos:user:create` fail —
  [issues/wallabag.md](../../issues/wallabag.md).
