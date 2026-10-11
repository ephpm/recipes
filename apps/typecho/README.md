# Typecho on ePHPm

| | |
|---|---|
| App | [Typecho](https://typecho.org) 1.3.0 (`TYPECHO_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm (the `joyqi/typecho` images) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | `compose.sqlite.yml` — Typecho's own `Pdo_SQLite` adapter (not ePHPm's embedded database) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`, `compose.sqlite.yml`): image build, Typecho's CLI installer on first start, home page, admin login through the login form, a post published through the editor form, the post on the home page and at its `/index.php/archives/<id>/` URL, `config.inc.php` and `var/` refused |

## What changes versus nginx + php-fpm

* **One process.** ePHPm serves the files and runs PHP; the rewrite to
  `index.php` is `[server] fallback`. Typecho computes its route from
  `REQUEST_URI` itself, so both its default `/index.php/archives/1/`
  permalinks and rewritten ones (`/archives/1/`, after enabling them in
  Settings → Permalinks) work without `PATH_INFO`.
* **Installed on the first start** with Typecho's own CLI installer
  (`php install.php`), driven by the variables the `joyqi/typecho` image
  uses: `TYPECHO_SITE_URL`, `TYPECHO_DB_ADAPTER` (`Pdo_Mysql`,
  `Pdo_SQLite`, `Pdo_Pgsql`), `TYPECHO_DB_HOST`, `TYPECHO_DB_PORT`,
  `TYPECHO_DB_USER`, `TYPECHO_DB_PASSWORD`, `TYPECHO_DB_DATABASE`,
  `TYPECHO_DB_FILE`, `TYPECHO_DB_PREFIX`, `TYPECHO_DB_CHARSET`,
  `TYPECHO_DB_ENGINE`, `TYPECHO_USER_NAME`, `TYPECHO_USER_PASSWORD`,
  `TYPECHO_USER_MAIL`, `TYPECHO_LANG`. `TYPECHO_INSTALL=0` skips it (use
  the web installer at `/install.php` instead).
* **`config.inc.php` is kept in the `/data` volume** and copied into the
  web root on start (a symlink does not work: the file derives Typecho's
  root directory from `dirname(__FILE__)`). Uploads are a second volume.
* `config.inc.php`, `var/` (the code), `install/`, PHP under uploads and
  plugins, and any `usr/*.db` file are refused by `[server.security]
  blocked_paths`.

## Run

```bash
docker compose up -d                         # MariaDB; or: podman compose up -d
docker compose -f compose.sqlite.yml up -d   # one container, SQLite
open http://localhost:8080/admin/            # EPHPM_PORT=8090 ... — then TYPECHO_SITE_URL too
```

Log in with `TYPECHO_USER_NAME` / `TYPECHO_USER_PASSWORD` (set a real
password before the first start). `TYPECHO_SITE_URL` must be the public URL:
links and the login cookie are built from it.

```bash
docker compose exec ephpm ephpm php -r 'echo PHP_VERSION, "\n";'   # one-off PHP; Typecho has no CLI besides install.php
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release zip, onto `ephpm/ephpm` |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Waits for MySQL, runs the CLI installer on the first start, keeps `config.inc.php` in `/data`, starts `ephpm serve` |
| `compose.yml` | ePHPm + MariaDB |
| `compose.sqlite.yml` | Single container on SQLite |
| `test.sh` | The smoke test CI runs (`bash apps/typecho/test.sh`) |

## Configuration notes

* Themes and plugins live in the image (`usr/themes`, `usr/plugins`): add
  them by extending the `Dockerfile` (`COPY mytheme /app/usr/themes/mytheme`)
  and rebuilding.
* PHP code changes need a container restart (OPcache timestamp validation
  is off under `ephpm serve`; `ephpm cache reset` is a no-op on a single
  node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* Image uploads are stored as uploaded; Typecho does not resize them, so
  ePHPm's GD without JPEG/WebP (`issues/koel.md`) does not get in the way of
  the core — themes or plugins that make thumbnails with GD would. Not
  exercised by `test.sh`.
