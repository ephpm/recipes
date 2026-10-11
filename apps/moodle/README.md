# Moodle on ePHPm

| | |
|---|---|
| App | [Moodle](https://moodle.org) 5.3.0 (`MOODLE_VERSION` build arg, a git tag) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache/nginx + php-fpm + the system crontab entry for `admin/cli/cron.php` |
| Default stack | `compose.yml` — ePHPm + cron sidecar (same image) + PostgreSQL 17 |
| Single container | none — not attempted (Moodle supports PostgreSQL, MariaDB/MySQL and SQL Server only) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: `admin/cli/install_database.php` on first start, login, dashboard with theme CSS/JS, create a course through the course form and read it back, `admin/cli/cfg.php`, the cron sidecar completes a run |

Moodle has no official Docker image; this replaces the usual web server +
PHP-FPM + crontab setup from Moodle's installation guide.

## What changes versus a stock install

* **One web process.** ePHPm serves `public/` — the web root since Moodle
  5.1; `config.php`, `vendor/` and the admin CLI sit above it. Every URL
  that is not a file goes to `r.php`, Moodle's router
  (`$CFG->routerconfigured = true`).
* **No slash arguments.** Moodle normally serves files and theme assets as
  `pluginfile.php/1/...` / `theme/styles.php/boost/...`, which needs
  `PATH_INFO`. ePHPm has none, so `config.php` sets
  `$CFG->slasharguments = 0` and Moodle generates `?file=...` /
  `?theme=...` URLs instead (a supported Moodle setting).
* **`config.php` reads the environment** (`MOODLE_WWWROOT`,
  `MOODLE_DBTYPE`, `MOODLE_DBHOST`, `MOODLE_DBPORT`, `MOODLE_DBNAME`,
  `MOODLE_DBUSER`, `MOODLE_DBPASS`, `MOODLE_DBPREFIX`, `MOODLE_SSLPROXY`,
  `MOODLE_DATAROOT`); `moodledata` is the volume.
* **Installed on first start** with `admin/cli/install_database.php`
  (`MOODLE_ADMIN_USER`, `MOODLE_ADMIN_PASSWORD`, `MOODLE_ADMIN_EMAIL`,
  `MOODLE_SITE_FULLNAME`, `MOODLE_SITE_SHORTNAME`, `MOODLE_LANG`);
  later starts run `admin/cli/upgrade.php --non-interactive`.
* **Cron is the `cron` service**: the same image running
  `admin/cli/cron.php --keep-alive=0` every minute, once the server has
  installed or upgraded the database.
* **The container listens on the `MOODLE_WWWROOT` port.** Moodle redirects
  any request whose port differs from `wwwroot`'s, and reads the port from
  `SERVER_PORT` — which ePHPm (like nginx) sets to the port it listens on,
  not the one in the `Host` header ([`issues/moodle.md`](../../issues/moodle.md)).
  So with `MOODLE_WWWROOT=http://host:8090` the server listens on 8090 in the
  container and `compose.yml` publishes it 1:1. With a TLS proxy in front
  (`MOODLE_SSLPROXY=true`, an `https://` wwwroot without a port) it listens
  on 8080 as usual.
* `php` on PATH is a shim for `ephpm php -d max_input_vars=5000`: the CLI
  does not read `[php] ini_overrides`, and Moodle's installer and upgrader
  refuse to run with less than 5000.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # first start: ~1-2 minutes of installation
```

Browse to **exactly** the URL in `MOODLE_WWWROOT` (`http://localhost:8080`
by default; `EPHPM_PORT=8090` changes the port in both). Log in with
`MOODLE_ADMIN_USER` / `MOODLE_ADMIN_PASSWORD` (`admin` /
`Moodle-Admin-Pass-1` — change them, and `MOODLE_DBPASS`, in a `.env` file
before the first start).

```bash
docker compose exec ephpm php admin/cli/cfg.php --name=release
docker compose exec ephpm php admin/cli/purge_caches.php
docker compose exec ephpm php admin/cli/maintenance.php --enable
docker compose restart ephpm                    # after adding or upgrading plugins (reloads PHP code)
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | The git tag + `composer install --no-dev`, onto `ephpm/ephpm` |
| `config.php` | Moodle's config from the environment; router configured, slash arguments off |
| `ephpm.toml` | Server config: `public/` root, `r.php` fallback, 100 MiB uploads, `max_input_vars` |
| `entrypoint.sh` | Waits for the DB, install/upgrade, `ephpm serve` on the wwwroot port; `cron` mode |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/moodle/test.sh`) |

## Configuration notes

* Plugins: add them to the image (under `public/mod/...`, `public/blocks/...`,
  etc.) and rebuild, then `admin/cli/upgrade.php` runs on the next start.
  Installing plugins from the web UI writes into the code tree, which is in
  the image, not a volume — and OPcache does not check timestamps under
  `ephpm serve`, so run `docker compose restart ephpm` after any code change
  (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).
* Sessions are Moodle's file sessions in `moodledata`. Moodle can use Redis
  for sessions/MUC; ePHPm's built-in KV is not wired up here.
* On PHP 8.5 the CLI prints deprecation notices (`xml_parser_free()`,
  backtick operator) from Moodle's own code; harmless, and not shown in web
  responses.

## Known limitations

* Slash arguments are off (above): URLs of files and assets look like
  `pluginfile.php?file=/...`. Everything works, but some third-party plugins
  that hard-code slash-argument URLs will not.
* GD in ePHPm has no JPEG/WebP/FreeType: user pictures and course images in
  JPEG cannot be resized into thumbnails.
