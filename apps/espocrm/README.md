# EspoCRM on ePHPm

| | |
|---|---|
| App | [EspoCRM](https://www.espocrm.com) 10.0.9 (`ESPOCRM_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.4` (the official image ships PHP 8.4) |
| Replaces | the official `espocrm/espocrm` image (apache or php-fpm) plus its `espocrm-daemon` container |
| Default stack | `compose.yml` — ePHPm + the scheduler + MariaDB 11 |
| Single container | not available — EspoCRM is MySQL/MariaDB/PostgreSQL only and its schema builder emits MySQL DDL the embedded database rejects (same class of gap as [issues/shlink.md](../../issues/shlink.md)) |
| Status | tested 2026-10-11 on v0.11.3-php8.4: install (schema, admin, config) by the entrypoint, client app and its assets served, API login as the client does it, an Account created and read back through the API, `config:get` on the console |

## What changes versus the official image

* **One web process, one scheduler service.** ePHPm serves the application
  root and runs PHP; `cron` runs the documented crontab (`cron.php` every
  minute) in a second container from the same image. The official
  `espocrm-daemon` is a forking job daemon (`daemon.php`, pcntl); this
  recipe sets `jobRunInParallel = false` and uses the plain cron entry point
  instead, so jobs run sequentially.
* **The Apache rewrite rules are a front controller.** EspoCRM's root
  `.htaccess` rewrites everything but `client/` into `public/`, and
  `public/api/v1/.htaccess` / `public/portal/.htaccess` route into their own
  entry points (nginx needs a `location` block each). ePHPm has one
  `[server] fallback` chain, so `front.php` (`/ephpm-front.php`) does that
  dispatch, setting `SCRIPT_NAME` the way Apache would so EspoCRM's base-path
  detection works — see [issues/espocrm.md](../../issues/espocrm.md).
  `client/` is served as static files straight from the application root.
* **Same environment variables as `espocrm/espocrm`:** `ESPOCRM_DATABASE_*`,
  `ESPOCRM_ADMIN_USERNAME`, `ESPOCRM_ADMIN_PASSWORD`, `ESPOCRM_SITE_URL`,
  `ESPOCRM_LANGUAGE`, `ESPOCRM_DATE_FORMAT`, `ESPOCRM_TIME_FORMAT`,
  `ESPOCRM_TIME_ZONE`, `ESPOCRM_WEEK_START`, `ESPOCRM_DEFAULT_CURRENCY`, and
  `ESPOCRM_CONFIG_<KEY>` for any `config.php` key. `entrypoint.sh` runs the
  official entrypoint's install/migrate steps on the embedded PHP.
* **Release zip, no build.** The image downloads `EspoCRM-<version>.zip`
  (vendor and the compiled client included) and removes the web installer,
  as the official image does.
* **The console runs on the embedded PHP:**
  `docker compose exec ephpm espocrm rebuild` (`espocrm` wraps
  `ephpm php command.php`, i.e. `bin/command`).

## Run

```bash
ESPOCRM_ADMIN_PASSWORD=change-me docker compose up -d
open http://localhost:8080     # admin / change-me
```

`ESPOCRM_SITE_URL` must be the URL users open
(`EPHPM_PORT=8090 ESPOCRM_SITE_URL=http://localhost:8090 …`).

```bash
docker compose exec ephpm espocrm rebuild
docker compose exec ephpm espocrm clear-cache
docker compose exec ephpm espocrm upgrade              # after bumping ESPOCRM_VERSION
docker compose logs -f cron
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release zip onto the `ephpm/ephpm` image |
| `front.php` | The prefix dispatcher that replaces the `.htaccess` rewrites |
| `ephpm.toml` | Server config (app-root docroot, fallback to the front controller, blocked paths, limits) |
| `entrypoint.sh` | Seeds the volumes, installs or migrates, applies `ESPOCRM_CONFIG_*`, starts `ephpm serve` (or the cron loop) |
| `espocrm` | `bin/command` wrapper over the embedded PHP |
| `compose.yml` | ePHPm + cron + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/espocrm/test.sh`) |

## Configuration notes

* `data/` (config, cache, uploads, logs), `custom/` and `client/custom` are
  volumes, as in the official image.
* `[server.security] blocked_paths` denies what the root `.htaccess` denies
  (`data/`, `application/`, `custom/`, `vendor/`, direct `public/` access)
  plus the root-level CLI scripts.
* Uploads: `[server.request] max_body_size` is 50 MiB and the ini overrides
  match the official `espocrm.ini` (`memory_limit=256M`,
  `max_execution_time=180`, 50M uploads).
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and an `https://` `ESPOCRM_SITE_URL`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default). After
  installing an extension or upgrading from the admin UI run
  `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* No WebSocket server (`websocket.php` needs the `zmq`/`ev` extensions,
  which are not in the ePHPm build); the client falls back to polling.
* `ldap` (LDAP authentication) and `imap` are not available; the official
  image includes `ldap`. E-mail works over SMTP.
* Jobs run from the cron loop sequentially (`jobRunInParallel = false`);
  the official daemon runs them in parallel with pcntl.
* PostgreSQL is supported by EspoCRM (`ESPOCRM_DATABASE_PLATFORM=Postgresql`)
  but not covered by the smoke test.
