# Piwigo on ePHPm

| | |
|---|---|
| App | [Piwigo](https://piwigo.org) 16.4.0 (`PIWIGO_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` (+ Debian's ImageMagick) |
| Replaces | Apache/nginx + php-fpm (the `linuxserver/piwigo` image) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not offered (Piwigo supports only MySQL/MariaDB; not tried on ePHPm's embedded database) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: unattended install on first start, admin login through the web API, create an album, upload a JPEG, read the album and photo back, square thumbnail generated (200 `image/jpeg`), credentials/installer files 403 |

## What changes versus the usual setup

* **One process.** ePHPm serves the gallery and runs PHP. Piwigo's URLs are
  query-string based (`index.php?/category/1`, `i.php?/upload/…`), so no
  rewrite rules are needed; `[server] fallback` ends in `=404` so unknown
  paths are 404s as with a plain Apache vhost.
* **JPEG thumbnails through ImageMagick.** ePHPm's built-in GD has no JPEG or
  WebP support (`issues/koel.md`), so the image installs Debian's
  `imagemagick` and Piwigo's `graphics_library = 'auto'` picks it
  (`ext_imagick`, it runs `convert`). Uploads, thumbnails and resized
  versions of JPEG/PNG/GIF work; WebP/HEIC depend on what Debian's
  ImageMagick 6 can decode.
* **Unattended install.** With `PIWIGO_ADMIN_PASSWORD` set (as in
  `compose.yml`), the entrypoint runs Piwigo's own `install.php` from the CLI
  on the first start with the `PIWIGO_*` values below (no newsletter
  subscription, no credentials e-mail). Leave the password empty to use the
  web installer at `/install.php` instead.
* **Production error settings.** Piwigo's defaults turn `display_errors` on
  from PHP; on PHP 8.5 its deprecation notices then appear in pages and in
  API responses before the headers (which breaks the login cookie). The
  entrypoint seeds `local/config/config.inc.php` with
  `show_php_errors_on_frontend = false` and deprecations filtered out; edit
  it in the `local` volume.

## Environment

| Variable | Default (compose) | Meaning |
|---|---|---|
| `PIWIGO_DB_HOST` | `db` | MySQL/MariaDB host (`host:port` accepted) |
| `PIWIGO_DB_NAME` / `PIWIGO_DB_USER` / `PIWIGO_DB_PASSWORD` | `piwigo` | database credentials |
| `PIWIGO_DB_PREFIX` | `piwigo_` | table prefix (install only) |
| `PIWIGO_ADMIN_USER` / `PIWIGO_ADMIN_PASSWORD` / `PIWIGO_ADMIN_EMAIL` | `admin` / `change-me-please` / `admin@example.com` | webmaster account (install only) |
| `PIWIGO_LANGUAGE` | `en_UK` | default language (install only) |

The `PIWIGO_*` names are this recipe's (the linuxserver image has none: it
always uses the web installer). After the first start the database settings
live in `local/config/database.inc.php`.

## Run

```bash
PIWIGO_ADMIN_PASSWORD='something-long' docker compose up -d   # or: podman compose up -d
open http://localhost:8080        # EPHPM_PORT=8090 docker compose up -d to change
```

Log in as `admin` with that password. Piwigo builds absolute URLs from the
request's `Host`, so no site-URL variable is needed.

```bash
docker compose exec ephpm php -r 'echo PHP_VERSION, "\n";'   # `php` is a shim for `ephpm php`
docker compose exec ephpm convert -version                   # the ImageMagick Piwigo uses
docker compose logs ephpm                                     # PHP errors and ePHPm's log
```

Photos can also be placed in the `galleries` volume and imported with
Admin → Tools → Synchronize, as upstream documents.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Release tag's tree onto `ephpm/ephpm`, plus ImageMagick |
| `ephpm.toml` | Server config (no rewrites, `=404` fallback, blocked paths) |
| `entrypoint.sh` | Seeds the volumes and `local/config/config.inc.php`, waits for the DB, runs the unattended install, starts `ephpm serve` |
| `install.php` | The CLI driver for Piwigo's installer |
| `php` | `php` on PATH → `ephpm php` |
| `compose.yml` | The stack: ePHPm + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/piwigo/test.sh`) |

## Configuration notes

* Volumes: `local` (`database.inc.php`, `config.inc.php`, local CSS and
  language overrides), `_data` (generated thumbnails/resizes, compiled
  templates, logs), `upload` (photos uploaded through the web/API) and
  `galleries` (photos synchronised from disk). Plugins and themes installed
  from the admin UI go into `plugins/` and `themes/` inside the container,
  which are **not** volumes: they survive restarts but not a container
  re-create. Bake them into the image (`COPY myplugin /var/www/html/plugins/myplugin`)
  or add volumes for those two directories.
* `blocked_paths` refuses `local/config/`, `_data/logs/`, `_data/templates_c/`,
  `_data/cache/`, `install/` and `include/`.
* Uploads: `max_body_size`, `upload_max_filesize` and `post_max_size` are
  100 MiB; the web uploader sends photos in chunks anyway.
* `max_execution_time` is 240 s and `memory_limit` 512M for resizing large
  photos.
* OPcache runs with timestamp validation off (ePHPm's `serve` default):
  after installing or updating plugins/themes from the admin UI run
  `docker compose restart ephpm` so the new PHP code is loaded.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`.

## Known limitations

* PHP 8.5 deprecation notices from Piwigo 16.4 are filtered out of the log
  by the seeded config; remove the `show_php_errors` line to see them.
* No video thumbnails (no `ffmpeg` in the image) and no `ext-imagick`
  (the external `convert` is used instead).
