# MediaWiki on ePHPm

| | |
|---|---|
| App | [MediaWiki](https://www.mediawiki.org) 1.46.2 (`MEDIAWIKI_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the `mediawiki:apache` image) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | `compose.sqlite.yml` — MediaWiki's own SQLite backend (supported upstream, not experimental) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (both variants): CLI install on first start, API login, create a page through the API and read it back on the web, Recent Changes, `maintenance/run.php Version` + `showSiteStats` on the embedded PHP, config/code paths 403 |

## What changes versus the official image

* **One process.** ePHPm serves the files and runs PHP. `includes/
  languages/ maintenance/ vendor/ cache/ sql/`, `LocalSettings.php` and PHP
  under `images/` are refused with `[server.security] blocked_paths`
  (MediaWiki's `images/.htaccess` turns the PHP engine off there).
* **Installed from the environment.** The official image ships no
  installer automation: you run the web installer and copy the generated
  `LocalSettings.php` into the container. Here the first start runs
  MediaWiki's own CLI installer (`maintenance/run.php install`) from the
  `MEDIAWIKI_*` variables and keeps `LocalSettings.php` in the `config`
  volume (symlinked into the web root). Leave `MEDIAWIKI_ADMIN_PASS` empty
  to use the web installer at `/mw-config/` instead and drop its
  `LocalSettings.php` into the `config` volume.
* **Plain URLs.** `$wgUsePathInfo = false` is appended to the generated
  `LocalSettings.php`: pages are `index.php?title=Page`. MediaWiki's
  "short URLs" (`/wiki/Page`) need a regex rewrite and `index.php/Page`
  needs `PATH_INFO`; ePHPm provides neither.
* **`php` on PATH is the embedded CLI**, so the maintenance scripts run as
  documented: `docker compose exec ephpm php maintenance/run.php update`.
* Sessions and caches are MediaWiki's own (object cache / database), as in
  the official image; nothing is moved to the KV store.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 ... — then set
                               # MEDIAWIKI_SITE_SERVER=http://localhost:8090 as well
```

The first start takes ~30 s (installer). Log in as `MEDIAWIKI_ADMIN_USER` /
`MEDIAWIKI_ADMIN_PASS` (`admin` / `mediawiki-admin-password` by default —
change them in `compose.yml` or a `.env` file). `MEDIAWIKI_SITE_SERVER`
**must** be the public URL: MediaWiki builds absolute links from it.

Variables (first start only, except `MEDIAWIKI_SITE_SERVER` which is baked
into `LocalSettings.php`): `MEDIAWIKI_SITE_NAME`, `MEDIAWIKI_SITE_SERVER`,
`MEDIAWIKI_SITE_LANG`, `MEDIAWIKI_ADMIN_USER`, `MEDIAWIKI_ADMIN_PASS`,
`MEDIAWIKI_DB_TYPE` (`mysql` | `sqlite`), `MEDIAWIKI_DB_HOST`,
`MEDIAWIKI_DB_NAME`, `MEDIAWIKI_DB_USER`, `MEDIAWIKI_DB_PASSWORD`.

```bash
docker compose exec ephpm php maintenance/run.php update --quick   # after upgrading the image
docker compose exec ephpm php maintenance/run.php runJobs          # the job queue
docker compose exec ephpm php maintenance/run.php showSiteStats
docker compose restart ephpm                                        # after editing PHP / adding extensions (reloads PHP code)
```

### Single container, MediaWiki's own SQLite

```bash
docker compose -f compose.sqlite.yml up -d
```

MediaWiki's SQLite backend (`pdo_sqlite`; database files under
`/var/www/data`, the `data` volume). No database server. Fine for small
wikis; MediaWiki documents its limits.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release tarball (vendor included), copies it onto `ephpm/ephpm` |
| `ephpm.toml` | Server config: 100 MiB uploads, blocked PHP-only paths |
| `php` | `php` → `ephpm php` shim for the maintenance scripts |
| `entrypoint.sh` | Waits for the DB, runs the CLI installer on first start, links `LocalSettings.php`, starts `ephpm serve` |
| `compose.yml`, `compose.sqlite.yml` | The two stacks |
| `test.sh` | The smoke test CI runs (`bash apps/mediawiki/test.sh`) |

## Configuration notes

* Edit `LocalSettings.php` in the `config` volume (`docker compose exec
  ephpm vi /var/www/config/LocalSettings.php` — or copy it out and back);
  the generated file already enables uploads into the `images` volume.
* Extensions and skins go into the image (`extensions/`, `skins/`): add
  `COPY` lines or a `git clone` to the Dockerfile, then `wfLoadExtension()`
  in `LocalSettings.php`.
* Uploads: `[server.request] max_body_size` (100 MiB) and the
  `upload_max_filesize` / `post_max_size` ini overrides move together with
  `$wgMaxUploadSize`.
* The job queue runs on page views by default (`$wgJobRunRate`); for a
  real schedule run `maintenance/run.php runJobs` from a host cron or an
  extra compose service.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and use the `https://` URL in `MEDIAWIKI_SITE_SERVER`.

## Known limitations

* No short URLs (see above).
* `imagick` is not available; thumbnails use GD (`$wgUseImageMagick =
  false` is MediaWiki's default). SVG rendering needs `rsvg`/ImageMagick,
  which this image does not have.
* No ePHPm-embedded-database variant was attempted (MediaWiki's MySQL
  schema uses binary charsets and other MySQL-specific DDL); use the SQLite
  stack for a single container.
