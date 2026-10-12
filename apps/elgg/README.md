# Elgg on ePHPm

| | |
|---|---|
| App | [Elgg](https://elgg.org) 7.1.1 (`ELGG_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache (`install/config/htaccess.dist`) or nginx (`nginx.dist`) + php-fpm, and the system crontab entry for `elgg-cli cron` (there is no official image) |
| Default stack | `compose.yml` — ePHPm + a cron service on the same image + MariaDB 11 |
| Single container | none — not tried against ePHPm's embedded database |
| Status | tested 2026-10-11 on v0.11.3-php8.5: `elgg-cli install` on first start, home page, simplecache CSS through `index.php`, login through the form (CSRF token), add a bookmark through its form and read it back, `elgg-cli cron`, restart runs `elgg-cli upgrade`, `settings.php`/`vendor`/web installer 403 |

## What changes versus the documented setup

* **One process serves the site.** ePHPm serves the project root with
  `nginx.dist`'s `try_files $uri $uri/ @elgg` as `[server] fallback`
  (simplecache under `/cache/` included). The paths `htaccess.dist` forbids
  are refused with `blocked_paths` (`vendor/`, `elgg-config/` — which holds
  `settings.php` with the DB password — `mod/`, `composer.*`), and so is the
  web installer, `install.php`.
* **Installed by `elgg-cli install`** on the first start, from environment
  variables, instead of the web installer. Later starts run
  `elgg-cli upgrade async`.
* **Cron** is a second service on the same image running `elgg-cli cron`
  every minute (what upstream asks for in the system crontab).
* `/usr/local/bin/elgg-cli` wraps `ephpm php vendor/bin/elgg-cli` with
  `session.use_cookies=0` and an empty `session.cache_limiter`: under
  `ephpm php`, `headers_sent()` is true from the start (`issues/wallabag.md`),
  and Symfony refuses to start the session Elgg opens on boot unless it
  sends no cookie and no cache headers.

## Run

```bash
ELGG_ADMIN_PASSWORD='at-least-16-characters' docker compose up -d   # or: podman compose up -d
open http://localhost:8080          # log in as admin
```

`ELGG_WWWROOT` (default `http://localhost:${EPHPM_PORT:-8080}/`) must be
the URL the site is opened at, with the trailing slash; it is stored in
the database at install time. Other first-start variables:
`ELGG_ADMIN_USERNAME`, `ELGG_ADMIN_EMAIL`, `ELGG_SITE_NAME`,
`ELGG_SITE_EMAIL`, `ELGG_TIMEZONE`, `ELGG_DB_PREFIX`; the `ELGG_DB_*`
variables are used by the installer and the database wait. Elgg 7 requires
an admin password of at least 16 characters; a shorter one makes the install
stop after the schema with "Unable to create an admin account" — drop the
volumes and start again.

```bash
docker compose exec ephpm elgg-cli plugins:list
docker compose exec ephpm elgg-cli cache:clear
docker compose exec ephpm elgg-cli upgrade async
```

## Known limits

* **No JPEG/WebP in GD.** ePHPm's GD has PNG and GIF only, so avatar, group
  icon, file thumbnail and cover image uploads in JPEG/WebP fail to resize;
  PNG/GIF work.
* `elgg-cli` prints a harmless `session_name(): Session name cannot be
  changed after headers have already been sent` warning (same
  `headers_sent()` cause).
* Volumes: `elgg-config` (`settings.php`) and `elgg-data` (the data
  directory: uploads, caches). Both must be kept together with the database.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release package (starter project with `vendor/`), copies it onto `ephpm/ephpm` |
| `ephpm.toml` | Server config: `nginx.dist` routing, `htaccess.dist` denials |
| `entrypoint.sh` | Waits for the DB, `elgg-cli install` on first start / `upgrade` afterwards, starts `ephpm serve` |
| `elgg-cli` | `ephpm php vendor/bin/elgg-cli` with the CLI session settings |
| `compose.yml` | The stack (ePHPm, cron, MariaDB) |
| `test.sh` | The smoke test (`bash apps/elgg/test.sh`) |
