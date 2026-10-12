# Open Source Point of Sale on ePHPm

| | |
|---|---|
| App | [Open Source Point of Sale](https://github.com/opensourcepos/opensourcepos) 3.4.2 (`OSPOS_VERSION` / `OSPOS_ASSET` build args) — CodeIgniter 4.7 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.4` (upstream supports PHP 8.2–8.4) |
| Replaces | the `jekkos/opensourcepos` image (Apache + mod_php) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not offered (not tried on ePHPm's embedded database) |
| Status | tested 2026-10-11 on v0.11.3-php8.4: migrations + secret provisioning on start, login as the default admin, create a customer through the customer form (CSRF), find it through the customer search, 404 pages, nothing above `public/` served |

## What changes versus the upstream image

* **One process.** ePHPm serves `public/` and runs PHP; the `.htaccess`
  rewrite to `index.php` is `[server] fallback`. `app/`, `vendor/`,
  `writable/` and `.env` are outside the document root.
* **Migrations run on start** (`php spark migrate --all`), then the
  secrets are provisioned (`php spark env:provision`, upstream's compose
  command). Upstream's compose seeds the database from an SQL dump instead
  and lets the app migrate on first access; `env:provision` fails on an empty
  database, so the order matters.
* **`.env` lives in the `writable` volume.** The app rewrites `.env` to store
  its generated `encryption.key` and `throttle.key`; upstream bind-mounts a
  host file for that. Here the entrypoint copies `writable/.env` into place
  on start and back after provisioning. `ENCRYPTION_KEY` / `THROTTLE_KEY`
  in the environment still win, as upstream documents.
* **`spark` is fetched from the tag.** The release zip has no `spark` CLI
  entry point; the Dockerfile downloads it from the same git tag.
* **CodeIgniter's exception handler is patched** so 404 and error pages are
  delivered instead of a bare 500 (ePHPm bug, `issues/opensourcepos.md`).

## Environment

Same names as the upstream image:

| Variable | Default (compose) | Meaning |
|---|---|---|
| `CI_ENVIRONMENT` | `production` | `development` shows CodeIgniter's debug toolbar and errors |
| `ALLOWED_HOSTNAMES` | `localhost:8080,localhost` | Host-header whitelist (required). OSPOS builds its URLs from the matching entry, so include the port when it is not 80/443 |
| `FORCE_HTTPS` | `false` | `true` behind a TLS-terminating proxy |
| `MYSQL_HOST_NAME` / `MYSQL_DB_NAME` / `MYSQL_USERNAME` / `MYSQL_PASSWORD` | `db` / `ospos` / `ospos` / `ospos` | database |
| `ENCRYPTION_KEY` / `THROTTLE_KEY` | generated | optional fixed secrets (hex) |

Upstream's `PHP_TIMEZONE` is not read (it sets `date.timezone` in the
Apache image); set the store's timezone in Office → Configuration → Locale.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 ... to change — then also
                               # ALLOWED_HOSTNAMES=localhost:8090
```

Log in as `admin` / `pointofsale` and change the password (Employees).

```bash
docker compose exec ephpm php spark migrate:status     # `php` is a shim for `ephpm php`
docker compose exec ephpm php spark list
docker compose logs ephpm
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Release zip (with `vendor/`) + `spark` onto `ephpm/ephpm`, exception-handler patch |
| `ephpm.toml` | Server config (`public/` root, front-controller fallback) |
| `entrypoint.sh` | Seeds the volumes, restores `.env`, waits for the DB, migrates, provisions secrets, starts `ephpm serve` |
| `php` | `php` on PATH → `ephpm php` |
| `compose.yml` | The stack: ePHPm + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/opensourcepos/test.sh`) |

## Configuration notes

* Volumes: `writable` (`.env`, logs, cache, sessions, backups) and
  `uploads` (`public/uploads`: item pictures, company logo).
* Logging is off (`logger.threshold=0` in the shipped `.env`); edit
  `writable/.env` and restart to raise it.
* `public/.htaccess` also sets security headers (CSP, `X-Frame-Options`,
  `nosniff`); ePHPm does not read `.htaccess`, so they are not sent. Add
  them at your TLS proxy, or with ePHPm's `security_headers` middleware.
* OPcache runs with timestamp validation off (`ephpm serve` default):
  restart the container after changing PHP files.

## Known limitations

* **Item pictures: PNG/GIF only.** ePHPm's GD has no JPEG/WebP support
  (`issues/koel.md`); OSPOS processes item images with GD, so JPEG uploads
  are expected to fail (not exercised by `test.sh`).
* Barcode/receipt printing, Mailchimp and SMS integrations are untested.
