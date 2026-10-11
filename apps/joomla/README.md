# Joomla on ePHPm

| | |
|---|---|
| App | [Joomla!](https://www.joomla.org) 6.1.4 (`JOOMLA_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the official `joomla` image) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | none — not attempted (Joomla supports MySQL/MariaDB and PostgreSQL only) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: CLI install on first start, administrator login, create an article in the editor and read it back in the admin list and on the site (query-string, `/index.php/...` and rewritten SEF URLs), `cli/joomla.php` on the embedded PHP, private files 403 |

## What changes versus the official image

* **One process.** ePHPm serves the site and `/administrator/`. The
  `htaccess.txt` front-controller rule is `[server] fallback`, so SEF URLs
  work with or without `index.php` in them (turn on *Use URL Rewriting* in
  Global Configuration to drop it from generated links).
* **Same environment variables.** `JOOMLA_DB_HOST`, `JOOMLA_DB_USER`,
  `JOOMLA_DB_PASSWORD` (or `JOOMLA_DB_PASSWORD_FILE`), `JOOMLA_DB_NAME`,
  `JOOMLA_DB_TYPE`, `JOOMLA_DB_PREFIX`, and for the unattended install
  `JOOMLA_SITE_NAME`, `JOOMLA_ADMIN_USER`, `JOOMLA_ADMIN_USERNAME`,
  `JOOMLA_ADMIN_PASSWORD` (more than 12 characters), `JOOMLA_ADMIN_EMAIL`,
  plus `JOOMLA_EXTENSIONS_URLS` / `JOOMLA_EXTENSIONS_PATHS` and
  `JOOMLA_SMTP_HOST` — the official entrypoint's behaviour, with Apache
  taken out. Without the site/admin variables the web installer runs.
* **The whole tree is the volume**, as in the official image: Joomla
  installs extensions, templates and its own updates into its code
  directories, so `/var/www/html` is seeded from the image on first start
  and then belongs to the site. Upgrade Joomla from the administrator (or
  `cli/joomla.php core:update`), not by rebuilding the image.
* **OPcache checks timestamps** (`opcache_validate_timestamps = true`,
  every 2 s). `ephpm serve` turns that off by default, but Joomla rewrites
  `configuration.php` when Global Configuration is saved and replaces its
  own PHP files on updates; without timestamp checks the old code would keep
  running.
* **The base image's test files are removed.** `ephpm/ephpm:v0.11.3` ships
  ePHPm's E2E fixtures (`info.php` = `phpinfo()`, ...) in `/var/www/html`;
  the Dockerfile deletes them so they never land in the site volume
  ([`issues/joomla.md`](../../issues/joomla.md)).

## Run

```bash
docker compose up -d                          # or: podman compose up -d
open http://localhost:8080                    # EPHPM_PORT=8090 ... to change
open http://localhost:8080/administrator/     # admin / joomla-admin-password
```

Change `JOOMLA_ADMIN_PASSWORD`, `JOOMLA_DB_PASSWORD` and `DB_ROOT_PASSWORD`
(in a `.env` file) before the first start; the admin account is created from
them once.

```bash
docker compose exec ephpm php cli/joomla.php list
docker compose exec ephpm php cli/joomla.php config:get sitename
docker compose exec ephpm php cli/joomla.php extension:install --url https://.../ext.zip
docker compose exec ephpm php cli/joomla.php core:update
```

`php` in the image is a shim for `ephpm php`.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Full release package into `/usr/src/joomla`, onto `ephpm/ephpm` (fixtures removed) |
| `ephpm.toml` | Server config: front-controller fallback, 64 MiB uploads, OPcache timestamp checks, private paths |
| `entrypoint.sh` | Seeds the volume, waits for the DB, unattended install, extensions/SMTP, `ephpm serve` |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/joomla/test.sh`) |

## Configuration notes

* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and *Force HTTPS* / `$live_site` in Global Configuration as needed.
* Joomla's scheduled tasks run on page views (*lazy scheduler*) by default;
  for a real cron run `php cli/joomla.php scheduler:run` from a host cron or
  an extra compose service.

## Known limitations

* **The Web Services API (`/api/...`) does not work.** Apache sends `/api/*`
  to `api/index.php`; ePHPm has no per-prefix routing and no `PATH_INFO`,
  so `/api/v1/...` and `/api/index.php/v1/...` both fall through to the
  site's `index.php` and answer the site's 404. The site and administrator
  are unaffected.
* GD in ePHPm has no JPEG/WebP/FreeType: the media manager's image
  resizing/cropping and thumbnails work for PNG/GIF only.
