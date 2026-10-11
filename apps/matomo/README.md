# Matomo on ePHPm

| | |
|---|---|
| App | [Matomo](https://matomo.org) 5.14.1 (`MATOMO_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the `matomo:apache` image) or nginx + php-fpm (`matomo:fpm`) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | none — Matomo is MySQL/MariaDB only, and its schema (e.g. `ALTER DATABASE … CHARACTER SET`) is not accepted by ePHPm's embedded database (see `issues/kanboard.md` for the same constructs) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: web installer end to end (DB prefilled from the environment), super-user login, site list via the reporting API, a tracking hit counted by `Live.getCounters`, `./console core:version` + `core:archive` on the embedded PHP, private paths 403 |

## What changes versus the official image

* **One process.** ePHPm serves the files and runs PHP. The official nginx
  rules are mirrored with `[server.security] blocked_paths`: only
  `index.php`, `matomo.php`, `piwik.php` and `js/index.php` are reachable
  PHP; `config/ tmp/ core/ lang/ libs/ vendor/ node_modules/` and every
  other `.php` answer 403, while static assets are served from anywhere
  (plugin images, `matomo.js`). The hardening headers nginx adds are
  `[server.response] headers`.
* **Same environment variables as the official image.**
  `MATOMO_DATABASE_HOST`, `MATOMO_DATABASE_USERNAME`,
  `MATOMO_DATABASE_PASSWORD`, `MATOMO_DATABASE_DBNAME`,
  `MATOMO_DATABASE_TABLES_PREFIX`, `MATOMO_DATABASE_ADAPTER` (and their
  `*_FILE` secret variants) prefill the web installer — Matomo's own
  `FormDatabaseSetup` reads them. Everything else comes from the installer
  and `config/config.ini.php`.
* **Archiving on a schedule, optionally.** `MATOMO_ARCHIVE_INTERVAL=3600`
  runs `./console core:archive` from the entrypoint every hour (Matomo's
  recommended cron job; the official image leaves that to you). Unset,
  Matomo archives on page views, its default. Point `MATOMO_ARCHIVE_URL`
  at the public URL if it is not `http://127.0.0.1:8080/`.
* **`php` on PATH is the embedded CLI**, so `./console` runs as
  documented: `docker compose exec ephpm ./console core:update`.
* **Four volumes** hold what Matomo writes: `config` (`config.ini.php`),
  `plugins` (Marketplace installs), `misc/user` (custom logos), `tmp`
  (cache/assets — can be dropped). The official image volumes the whole
  web root instead.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

The first visit runs Matomo's installer: system check, database (prefilled
from the environment), tables, super user, first website, tracking code.
Afterwards:

```bash
docker compose exec ephpm ./console core:archive --url=http://localhost:8080/   # archive now
docker compose exec ephpm ./console plugin:activate CustomDimensions
docker compose exec ephpm ./console core:update                                 # after upgrading the image
docker compose restart ephpm                                                    # after plugin installs/updates (reloads PHP code)
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release zip (vendor included), copies it onto `ephpm/ephpm`, keeps pristine copies to seed the volumes |
| `ephpm.toml` | Server config: the nginx-equivalent path rules, 64 MiB bodies, 512M PHP memory |
| `php` | `php` → `ephpm php` shim for `./console` |
| `entrypoint.sh` | Seeds the volumes, waits for the DB, optional archive loop, `ephpm serve` |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/matomo/test.sh`) |

## Configuration notes

* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and Matomo's `[General] proxy_client_headers[] = HTTP_X_FORWARDED_FOR`,
  `assume_secure_protocol = 1` in `config/config.ini.php`.
* The `db` service runs with `--max-allowed-packet=64MB` (Matomo's
  recommendation); raise `[server.request] max_body_size` and the ini
  overrides together for larger log imports.
* GeoIP: Matomo's `GeoIp2` plugin downloads databases into `misc/` through
  the UI/console (`./console geoip2:update`); nothing is bundled.
* OPcache runs with timestamp validation off (`ephpm serve` default): run
  `docker compose restart ephpm` after installing or updating plugins (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* No single-container variant (see the table).
* The Matomo `Diagnostics` system check reports the missing optional
  `mysqli` driver as fine (`PDO\MYSQL` is used) but flags that
  `always_populate_raw_post_data` is irrelevant on PHP 8 — both harmless.
