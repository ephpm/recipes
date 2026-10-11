# Part-DB on ePHPm

| | |
|---|---|
| App | [Part-DB](https://part-db.de) 2.20.0 (`PARTDB_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the official `jbtronics/part-db1` image (Apache + php-fpm) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | `compose.sqlite.yml` — Part-DB's own SQLite file (the official image's default). ePHPm's embedded database is not shipped: Doctrine's MySQL DDL fails on it ([issues/shlink.md](../../issues/shlink.md)) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (MariaDB 11 and native SQLite: migrations + admin password by the entrypoint, login, homepage, new-category form, category tree, parts list, console) |

## What changes versus the official image

* **One process.** ePHPm serves `public/` and runs PHP; the Symfony rewrite
  from `public/.htaccess` is `[server] fallback` in `ephpm.toml`. The
  official Apache rule that refuses PHP under `public/media` is
  `[server.security] blocked_paths`.
* **Same environment variables as `jbtronics/part-db1`** — everything in
  Part-DB's `.env` (`DATABASE_URL`, `APP_SECRET`, `DEFAULT_LANG`,
  `DEFAULT_TIMEZONE`, `BASE_CURRENCY`, `INSTANCE_NAME`, `TRUSTED_PROXIES`,
  `TRUSTED_HOSTS`, `DB_AUTOMIGRATE`, `DEFAULT_URI`, mail, SAML, OAuth…).
  Part-DB reads them itself.
* **Two differences:** `APP_SECRET` is optional (generated once into the
  `db` volume when unset; the official image requires it), and
  `DB_AUTOMIGRATE` defaults to `true` here (migrations run on every start,
  with Part-DB's own backup into `uploads/.automigration-backup`) instead of
  requiring a manual `doctrine:migrations:migrate`. An `ADMIN_PASSWORD`
  variable sets the `admin` password on start; without it the first
  migration prints a random one in the container log, as upstream.
* **Release zip, no build.** The image downloads `partdb_with_assets.zip`
  (vendor and compiled `public/build` included); nothing runs Composer or
  Yarn. `COMPOSER_EXTRA_PACKAGES` is therefore not supported (the image has
  no Composer); `ephpm composer require` in a derived image is the equivalent.
* **The console runs on the embedded PHP:**
  `docker compose exec ephpm partdb partdb:users:set-password admin`
  (`partdb` wraps `ephpm php -d memory_limit=-1 bin/console`).

## Run

```bash
ADMIN_PASSWORD=change-me docker compose up -d      # or: podman compose
open http://localhost:8080     # admin / change-me
```

`DEFAULT_URI` is used for links in e-mails and QR codes; set it to the URL
users open (`EPHPM_PORT=8090 DEFAULT_URI=http://localhost:8090/ …`).

```bash
docker compose exec ephpm partdb partdb:version
docker compose exec ephpm partdb partdb:backup --full /var/www/html/uploads/backup.zip
docker compose exec ephpm partdb partdb:users:list
```

### Single container, Part-DB's SQLite (supported)

```bash
ADMIN_PASSWORD=change-me docker compose -f compose.sqlite.yml up -d
```

No database server: `var/db/app.db` in the `db` volume, with
`DATABASE_SQLITE_ENFORCE_FOREIGN_KEYS=1` as Part-DB recommends for new
instances.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release zip onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, blocked paths, upload limits) |
| `entrypoint.sh` | Seeds the volumes, resolves `APP_SECRET`, waits for the DB, migrates, sets the admin password, starts `ephpm serve` |
| `partdb` | `bin/console` wrapper over the embedded PHP |
| `compose.yml`, `compose.sqlite.yml` | The two stacks |
| `test.sh` | The smoke test CI runs (`bash apps/part-db/test.sh`) |

## Configuration notes

* `uploads/`, `public/media` and `var/db` are volumes, as in the official
  image.
* Uploads: `[server.request] max_body_size` is 300 MiB and
  `upload_max_filesize`/`post_max_size`/`max_input_vars` match the official
  image's `partdb.ini`.
* `APP_ENV=docker` (logs to stderr) is the official image's setting and the
  default here.
* Sessions: Part-DB uses Symfony's default PHP session handler, so
  `[php] ini_overrides = [["session.save_handler", "ephpm"]]` would move
  them into ePHPm's KV store (`framework.session.handler_id` is `null` in
  Part-DB's config). Not enabled by default.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  (ePHPm) and `TRUSTED_PROXIES` (Part-DB).
* OPcache runs with timestamp validation off (ePHPm's `serve` default). After
  changing PHP files run `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* The console wrapper runs as root (the image has no `www-data` switch), so
  Part-DB's "You are running this command as root" warning appears in the
  log on every start; it is harmless here because the web server runs as
  the same user.
* `imagick` is not available; image handling uses GD (compiled in).
