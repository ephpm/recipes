# Ampache on ePHPm

| | |
|---|---|
| App | [Ampache](https://ampache.org) 8.2.2 (`AMPACHE_VERSION` build arg; the `_all_php8.5` release) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` (Ampache 8 requires PHP 8.5) |
| Replaces | the `ampache/ampache` image (Apache + mod_php + cron under supervisord) |
| Default stack | `compose.yml` — ePHPm + a `cron` service on the same image + MariaDB 11 |
| Single container | not offered |
| Status | tested 2026-10-11 on v0.11.3-php8.5: CLI install on first start, login form, catalog created and scanned with `bin/cli`, song found and streamed through the JSON API, playlist created and read back, Subsonic `ping.view` through `front.php`, cron service running (with a one-line patch for an ePHPm bug, see below) |

## What changes versus the official image

* **One process serves the app.** ePHPm serves `public/`; `src/`, `config/`,
  `vendor/` and `bin/` are outside the document root, so most of
  `public/.htaccess.dist` is moot. `*.dist` files and Ampache's own
  `phpinfo.php` are refused.
* **Rewrites.** Ampache ships several `.htaccess.dist` files. ePHPm has one
  fallback chain per site (`issues/espocrm.md`), so the fallback is a small
  `ephpm-front.php` that maps the **Subsonic API** (`/rest/<action>.view` →
  `rest/index.php?ssaction=<action>`, which Subsonic clients need) and answers
  404 otherwise. Not mapped: the pretty `/rest/<version>/json/…` paths of
  Ampache's REST API (use `server/json.server.php` / `xml.server.php`, which
  every Ampache client supports), and the `/play/…` "beautiful stream URLs"
  (off by default, `stream_beautiful_url`).
* **CLI install on the first start.** `bin/installer install` creates the
  database, the `ampache` database user and `config/ampache.cfg.php` with the
  `AMPACHE_DB_ADMIN_*` account (as the web installer does), then
  `bin/cli admin:addUser … --level 100` creates the admin. Later starts run
  `bin/cli admin:updateDatabase --execute` for image upgrades.
* **Public host/port pinned.** Ampache builds absolute URLs (stream links,
  redirects) from `SERVER_NAME`/`SERVER_PORT` unless `http_host`/`http_port`
  are set; ePHPm reports its listen port, not the published one
  (`issues/moodle.md`), so the entrypoint writes `AMPACHE_HTTP_HOST` /
  `AMPACHE_HTTP_PORT` into the config on every start. Set both to what users
  type in the browser (both are needed: with only a port, the CLI catalog
  scan fails on a null host).
* **ePHPm bug patched:** `filter_has_var(INPUT_SERVER, …)` is always false on
  ePHPm v0.11.3 (`issues/ampache.md`), so Ampache saw no client IP and denied
  every page by ACL. The Dockerfile rewrites the two calls in
  `src/Module/System/Core.php` to read `$_SERVER` directly.
* **Cron is a service.** `cron` runs `bin/cli run:cronProcess` hourly on the
  same image (the official image's crontab).

## Environment

| Variable | Default (compose) | Meaning |
|---|---|---|
| `AMPACHE_HTTP_HOST` / `AMPACHE_HTTP_PORT` | `localhost` / `${EPHPM_PORT:-8080}` | public host and port (written to `ampache.cfg.php` on every start) |
| `AMPACHE_DB_HOST` / `_PORT` / `_NAME` | `db` / `3306` / `ampache` | database |
| `AMPACHE_DB_USER` / `AMPACHE_DB_PASSWORD` | `ampache` / `ampache` | the account Ampache uses (created by the installer) |
| `AMPACHE_DB_ADMIN_USER` / `AMPACHE_DB_ADMIN_PASSWORD` | `root` / `root` | administrative account the installer uses to create the above |
| `AMPACHE_ADMIN_USER` / `AMPACHE_ADMIN_PASSWORD` | `admin` / — | the Ampache administrator (first start; no password → no user, add one with `bin/cli admin:addUser`) |
| `AMPACHE_WEB_PATH` | `""` | sub-path, if served below `/` behind a proxy |

The names are this recipe's; everything else is in `config/ampache.cfg.php`
(the `config` volume).

## Run

```bash
AMPACHE_ADMIN_PASSWORD='something-long' docker compose up -d   # or: podman compose up -d
open http://localhost:8080      # EPHPM_PORT=8090 ... changes the published port and http_port
```

Put music in the `media` volume (or replace it with a bind mount of your
library on `/media`) and add a catalog in the UI or with the CLI:

```bash
docker compose exec ephpm php bin/cli run:addCatalog music /media music
docker compose exec ephpm php bin/cli run:updateCatalog -a music
docker compose exec ephpm php bin/cli run:cronProcess
docker compose logs ephpm cron
```

`php` in the image is a shim for `ephpm php`. CLI commands print `ini_set(): Session ini
settings cannot be changed after headers have already been sent` warnings
(`ephpm php` reports headers as sent, `issues/wallabag.md`); they are harmless.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Release zip onto `ephpm/ephpm`, `INPUT_SERVER` patch, `front.php` |
| `front.php` | Fallback: Subsonic `/rest/*.view` → `rest/index.php`, else 404 |
| `ephpm.toml` | Server config (`public/` root, fallback to the front script) |
| `entrypoint.sh` | Seeds `config/`, waits for the DB, CLI install + admin, pins host/port, starts `ephpm serve` — or the cron loop |
| `php` | `php` on PATH → `ephpm php` |
| `compose.yml` | ePHPm + cron + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/ampache/test.sh`) |

## Known limitations

* **No transcoding** (no `ffmpeg` in the image): files are streamed as they
  are. Add `ffmpeg` in a derived image and configure `transcode_*` to enable
  it.
* **Streams are buffered.** ePHPm's per-request mode holds a response in
  memory until the script ends (`issues/librespeed.md`), so a stream starts
  only after the whole file has been read, and each concurrent stream costs
  the file's size in RAM. Fine for songs; poor for long podcasts or videos.
* **Album art: PNG/GIF only.** ePHPm's GD has no JPEG/WebP
  (`issues/koel.md`); JPEG covers cannot be resized (not exercised by
  `test.sh`).
* WebSocket server (`bin/cli run:websocket`) and UPnP are not set up.
