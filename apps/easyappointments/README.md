# Easy!Appointments on ePHPm

| | |
|---|---|
| App | [Easy!Appointments](https://easyappointments.org) 1.6.0 (`EA_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm (the upstream `docker-compose.yml`), or the official `alextselegidis/easyappointments` php-apache image |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not available — the app's migrations use `ALTER TABLE … ADD CONSTRAINT … FOREIGN KEY`, which the embedded database rejects ([issues/easyappointments.md](../../issues/easyappointments.md)) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: web installer completed over HTTP (schema + admin), login through `login/validate`, backend calendar and customers pages served |

## What changes versus the official image

* **One process.** ePHPm serves `assets/` and runs PHP; the front-controller
  rewrite (`try_files $uri $uri/ /index.php?$args` upstream) is
  `[server] fallback` in `ephpm.toml`. The app's own `/index.php/<controller>`
  links keep working: CodeIgniter strips the script name from `REQUEST_URI`
  itself, so no `PATH_INFO` splitting is involved.
* **Same environment variables as `alextselegidis/easyappointments`.**
  `BASE_URL`, `LANGUAGE`, `DEBUG_MODE`, `DB_HOST`, `DB_NAME`, `DB_USERNAME`,
  `DB_PASSWORD`, `GOOGLE_SYNC_FEATURE`, `GOOGLE_CLIENT_ID`,
  `GOOGLE_CLIENT_SECRET` and the `MAIL_*` set. `entrypoint.sh` writes
  `config.php` and `application/config/email.php` from them on every start,
  and pins `base_url` the way the official entrypoint does.
* **Release zip, no build.** The image downloads the
  `easyappointments-<version>.zip` release (vendor and compiled assets
  included); nothing runs Composer or npm.
* **The CLI runs on the embedded PHP:**
  `docker compose exec ephpm ephpm php index.php console <command>`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 BASE_URL=http://localhost:8090 docker compose up -d
```

The first visit redirects to the installer (`/index.php/installation`), which
creates the schema and the admin account. Afterwards:

```bash
docker compose exec ephpm ephpm php index.php console help
docker compose exec ephpm ephpm php index.php console backup   # into storage/backups
```

`BASE_URL` must be the URL users actually open: every link, redirect and
cookie is built from it.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release zip onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, blocked paths, upload limits) |
| `entrypoint.sh` | Writes `config.php` + `email.php` from the environment, waits for the DB, starts `ephpm serve` |
| `compose.yml` | ePHPm + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/easyappointments/test.sh`) |

## Configuration notes

* `storage/` (sessions, logs, cache, backups, uploads) is a volume and is
  blocked from the web (`[server.security] blocked_paths`), as are
  `application/`, `system/`, `vendor/` and `config.php` — what the shipped
  `.htaccess` files deny under Apache.
* Uploads: `[server.request] max_body_size` is 128 MiB (the upstream nginx
  `client_max_body_size`); `upload_max_filesize`/`post_max_size` are 100M as
  in the official image's `99-overrides.ini`.
* Sessions use CodeIgniter's `files` driver in `storage/sessions` (the app's
  default). The native `ephpm` session handler is not used: CodeIgniter 3
  runs its own session layer and never hands storage to PHP's save handler.
* Mail: `MAIL_PROTOCOL=mail` (the default) needs a `sendmail` binary, which
  the image does not have. Set `MAIL_PROTOCOL=smtp` and the `MAIL_SMTP_*`
  variables for notifications.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies` and
  an `https://` `BASE_URL`; the app then sets the `Secure` cookie flag itself
  (`cookie_secure` follows the `BASE_URL` scheme).
* OPcache runs with timestamp validation off (ePHPm's `serve` default). After
  changing PHP files run `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).
* Cron: Easy!Appointments has no cron jobs. Google Calendar sync and
  notifications run inline with requests.

## Known limitations

* No single-container variant: Easy!Appointments' migrations add foreign
  keys with `ALTER TABLE … ADD CONSTRAINT`, which SQLite has no equivalent
  for and the embedded database (Turso engine behind the MySQL listener)
  rejects. Details and a minimal repro in
  [issues/easyappointments.md](../../issues/easyappointments.md).
* LDAP login (`Settings > Integrations > LDAP`) needs the `ldap` PHP
  extension, which the ePHPm build does not include.
* `imagick` is not available; the app only uses GD, which is compiled in.
