# Nextcloud on ePHPm

| | |
|---|---|
| App | [Nextcloud](https://nextcloud.com) server 35.0.1 (`NEXTCLOUD_VERSION` build arg; 35 is the first major that accepts PHP 8.5) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` + APCu from the ePHPm extension catalog |
| Replaces | the `nextcloud:apache` image (Apache + mod_php), or `nextcloud:fpm` + an nginx container, and the `cron` container |
| Default stack | `compose.yml` — ePHPm + a background-jobs sidecar + MariaDB 11 |
| Single container | none — Nextcloud's migrations need a real MySQL/MariaDB/PostgreSQL (the embedded database rejects `ADD CONSTRAINT`, see `issues/bookstack.md`) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, install on the first request (autoconfig), login through the web login form, Files app page (`/apps/files/` and `/index.php/apps/files/`), WebDAV upload (PUT) + PROPFIND listing + download, OCS API user lookup, code/data directories refused, a background-job run through `/cron.php`. **`occ` does not run** (see Known limitations) |

## What changes versus the official image

* **One process serves Nextcloud.** ePHPm is the HTTP server and the PHP
  runtime. Front-controller routing (`/apps/files`, `/login`, …) is
  `[server] fallback`; the code and data directories nginx's reference config
  refuses (`/config`, `/data`, `/lib`, `/3rdparty`, `/templates`, `/build`,
  `/tests`, `/occ`, `/console*`, `/db_*`, …) are `[server.security]
  blocked_paths`, and dotfiles are refused by `hidden_files` (default).
* **`PATH_INFO` is emulated in userland.** Nextcloud's WebDAV
  (`/remote.php/dav/...`), OCS (`/ocs/v2.php/...`) and public-share
  (`/public.php/...`) URLs need nginx's `fastcgi_split_path_info`, which
  ePHPm v0.11.3 does not do. `ephpm-pathinfo.php`, loaded as
  `auto_prepend_file`, re-dispatches requests whose path names one of the
  entry points nginx's config allows (same regex) to that script, with
  `SCRIPT_NAME`, `SCRIPT_FILENAME`, `PHP_SELF` and `PATH_INFO` set as
  php-fpm would. Nextcloud's own files are not modified.
* **Installed through the web installer, on the first request.** The
  entrypoint writes `config/autoconfig.php` from the environment (as the
  official image does) and Nextcloud installs itself when the first page is
  requested — that request takes a minute or two. Not `occ
  maintenance:install`: see Known limitations.
* **Same variables as the official image:** `MYSQL_HOST`, `MYSQL_DATABASE`,
  `MYSQL_USER`, `MYSQL_PASSWORD`, `NEXTCLOUD_ADMIN_USER`,
  `NEXTCLOUD_ADMIN_PASSWORD`, `NEXTCLOUD_DATA_DIR`,
  `NEXTCLOUD_TABLE_PREFIX`, `NEXTCLOUD_TRUSTED_DOMAINS`,
  `OVERWRITEPROTOCOL`, `OVERWRITEHOST`, `OVERWRITECLIURL`,
  `TRUSTED_PROXIES`. Without the admin variables the browser shows the
  installer as usual.
* **`config/ephpm.config.php`** (rewritten from the image on every start)
  sets APCu as `memcache.local`, the `apps` / `custom_apps` paths of the
  official image, pretty URLs (`htaccess.RewriteBase`,
  `htaccess.IgnoreFrontController`) and the env-driven values above.
* **Background jobs** run from the `cron` service, which fetches
  `/cron.php` every 5 minutes. In Nextcloud's default "AJAX" mode each call
  runs one due job; set Administration → Basic settings → Background jobs to
  **Webcron** so each call runs all due jobs.
* **Volumes** as in the official image, but the code stays in the image:
  `config/`, `data/`, `custom_apps/`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # first load installs (1-2 min); EPHPM_PORT=8090 to change
```

Log in with `NEXTCLOUD_ADMIN_USER` / `NEXTCLOUD_ADMIN_PASSWORD` (set a real
password in `compose.yml` or a `.env` file before the first start). Add the
host name you open it at to `NEXTCLOUD_TRUSTED_DOMAINS`. Desktop and mobile
clients connect to `http://<host>:8080`; CalDAV/CardDAV clients need the full
URL `http://<host>:8080/remote.php/dav` (no `/.well-known` discovery, below).

```bash
curl -u admin:PASS -T file.txt http://localhost:8080/remote.php/dav/files/admin/file.txt   # WebDAV
docker compose exec ephpm ephpm kv keys '*'                                                 # the in-process KV store
docker compose logs ephpm cron                                                              # server and background jobs
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads and checksums the release tarball, adds APCu from the ePHPm extension catalog, onto `ephpm/ephpm` |
| `ephpm.toml` | Server config (routing, blocked paths, PHP ini, APCu, the PATH_INFO prepend) |
| `ephpm-pathinfo.php` | `auto_prepend_file`: `fastcgi_split_path_info` for Nextcloud's entry points |
| `ephpm.config.php` | Nextcloud config fragment (APCu, app paths, pretty URLs, env-driven proxy settings) |
| `entrypoint.sh` | Seeds `config/`, writes `autoconfig.php`, waits for the database, starts `ephpm serve` |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/nextcloud/test.sh`) |

## Configuration notes

* Uploads: 512 MiB per request (`[server.request] max_body_size`,
  `upload_max_filesize`, `post_max_size`); the web UI and the clients
  upload large files in chunks, so this is not a file-size limit.
* `[opcache] cluster_invalidation = true` is set so `docker compose exec
  ephpm ephpm cache reset` actually refreshes PHP code after an app update
  (on v0.11.3 it is a no-op without it, `issues/nextcloud.md`).
* Behind a TLS-terminating proxy set `OVERWRITEPROTOCOL=https`,
  `OVERWRITECLIURL`, `TRUSTED_PROXIES`, and `[server.security]
  trusted_proxies` in `ephpm.toml`.
* Upgrading: bump `NEXTCLOUD_VERSION`, rebuild, restart, and open the web
  page as admin — Nextcloud offers its web upgrade (not exercised here;
  there is no `occ upgrade`, below). Back up `data/`, `config/` and the database first.

## Known limitations

* **`occ` does not run** (nor `ephpm php cron.php`): under `ephpm php`,
  `headers_sent()` is true before any output (`issues/wallabag.md`), and
  Nextcloud's config loader treats that as "config file has leading content"
  and aborts. No maintenance mode, `files:scan`, `occ upgrade`, user or app
  management from the CLI — use the web UI and the OCS API. This is the
  biggest gap; it goes away when ePHPm fixes the CLI SAPI.
* **No `/.well-known` redirects** (CalDAV/CardDAV auto-discovery):
  ePHPm refuses every dot-segment path before PHP sees it
  (`issues/nextcloud.md`); point DAV clients at `/remote.php/dav`. The admin
  overview's setup checks warn about this.
* **Image previews**: ePHPm's GD has no JPEG/WebP/AVIF support
  (`issues/koel.md`), so no thumbnails for those formats (PNG/GIF work).
  Files themselves upload and download normally.
* Redis (distributed cache / file locking) is not configured or tested;
  file locking stays in the database (Nextcloud's default).
