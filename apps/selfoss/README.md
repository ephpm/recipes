# selfoss on ePHPm

| | |
|---|---|
| App | [selfoss](https://selfoss.aditu.de) 2.19 (`SELFOSS_VERSION` build arg; the latest tagged release, 2022) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache with selfoss's `.htaccess` (or nginx + php-fpm), and the cron job running `cliupdate.php` |
| Default stack | `compose.yml` — ePHPm + an `updater` service on the same image; selfoss's own SQLite database (no database server) |
| Single container | yes for serving (SQLite); the updater is a second container on the same volume |
| Status | tested 2026-10-11 on v0.11.3-php8.5: page and JS bundle served, login, add an RSS source, the updater's `cliupdate.php` fetches it, item read back through the JSON API, config/database/code 403 |

## What changes

* **The `.htaccess` is a fallback chain.** selfoss's Apache rules serve
  static assets from `public/`, favicons and thumbnails from `data/…`, and
  route everything else to `index.php`; in `ephpm.toml` that is
  `fallback = ["$uri", "/public$uri", "/data$uri", "/index.php?$query_string"]`.
  `blocked_paths` keeps `*.ini`, the SQLite database, logs, caches, `src/`,
  `vendor/` and the CLI scripts off the web (`.htaccess` only denies
  `*.ini`; the rest is not reachable there because of the rewrite).
* **Configured from the environment.** selfoss reads any `config.ini` key
  as `SELFOSS_<KEY>` (its `env_prefix`), so no `config.ini` is needed. The
  recipe adds `SELFOSS_PLAIN_PASSWORD`, hashed with `password_hash()` at
  start (what selfoss's `/password` page produces); `SELFOSS_PASSWORD`
  takes an existing hash. Leave both username and password empty and selfoss
  is open to anyone.
* **Feeds are refreshed by the `updater` service** — `cliupdate.php` every
  `SELFOSS_UPDATE_INTERVAL` seconds (900), the upstream cron job.
* Logs go to the container log (`SELFOSS_LOGGER_DESTINATION=error_log`).

## Run

```bash
SELFOSS_PLAIN_PASSWORD='something-long' docker compose up -d   # or: podman compose up -d
open http://localhost:8080        # log in as admin; EPHPM_PORT=8090 ... to change
docker compose exec updater php cliupdate.php     # refresh now (`php` is a shim for `ephpm php`)
docker compose logs ephpm updater
```

To use MySQL/MariaDB or PostgreSQL instead of SQLite, add the database
service and set `SELFOSS_DB_TYPE`, `SELFOSS_DB_HOST`, `SELFOSS_DB_DATABASE`,
`SELFOSS_DB_USERNAME`, `SELFOSS_DB_PASSWORD` (not exercised by `test.sh`).

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Release zip onto `ephpm/ephpm` |
| `ephpm.toml` | Server config (`.htaccess` as fallback chain + blocked paths) |
| `entrypoint.sh` | Seeds `data/`, hashes the password, starts `ephpm serve` — or the updater loop |
| `php` | `php` on PATH → `ephpm php` |
| `compose.yml` | ePHPm + updater, `data` volume |
| `test.sh` | The smoke test CI runs (`bash apps/selfoss/test.sh`) |

## Known limitations

* selfoss 2.19 is from 2022; it runs on PHP 8.5 in this test, but newer
  development happens on the main branch without tagged releases.
* **Thumbnails/favicons: PNG/GIF only.** ePHPm's GD has no JPEG/WebP
  (`issues/koel.md`), so JPEG thumbnails and icons are not generated (not
  exercised by `test.sh`).
* OPcache runs with timestamp validation off: restart after editing PHP
  (custom spouts).
