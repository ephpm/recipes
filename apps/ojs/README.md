# OJS (Open Journal Systems) on ePHPm

| | |
|---|---|
| App | [OJS](https://pkp.sfu.ca/software/ojs/) 3.5.0-4 (`OJS_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.4` |
| Replaces | the official `pkp/ojs` image (php-apache with `AcceptPathInfo` + mod_rewrite, cron) |
| Default stack | `compose.yml` — ePHPm + the scheduled-tasks runner + MariaDB 11 |
| Single container | not offered — OJS needs MySQL/MariaDB or PostgreSQL; an install on ePHPm's embedded MySQL-compatible database was not attempted |
| Status | tested 2026-10-11 on v0.11.3-php8.4: web installer completed over HTTP (schema + site admin), `installed = On` written to the config volume, login through the login form, site administration (Hosted Journals) served through the PATH_INFO front controller, `tools/upgrade.php check` on the embedded PHP |

## What changes versus the official image

* **`PATH_INFO` comes from a front controller.** OJS routes by
  `$_SERVER['PATH_INFO']` (`/index.php/<journal>/<page>/<op>`), which Apache
  provides with `AcceptPathInfo On` and `RewriteRule ^(.*)$ index.php/$1`.
  ePHPm does not set `PATH_INFO`, so `front.php` (`/ephpm-front.php`, the
  `[server] fallback` target) derives it from the request URI — for both
  `/index.php/...` URLs and `restful_urls = On` — and runs `index.php`. See
  [issues/espocrm.md](../../issues/espocrm.md).
* **Same environment variables as `pkp/containers`:** `PKP_DB_DRIVER`,
  `PKP_DB_HOST`, `PKP_DB_NAME`, `PKP_DB_USER`, `PKP_DB_PASSWORD`, plus
  `PKP_BASE_URL`, `PKP_ALLOWED_HOSTS`, `PKP_RESTFUL_URLS`,
  `PKP_SESSION_CHECK_IP` for the matching `config.inc.php` keys.
  `entrypoint.sh` writes `config.inc.php` from the template on first start
  (with generated `salt` / `api_key_secret`) into the `config` volume and
  links it into the application; the installer then completes it.
* **Installation is OJS's own web installer**, exactly as with the official
  image: open the site, fill in the admin account and the (prefilled)
  database settings. `test.sh` sends the same POST the official image's
  `PKP_CLI_INSTALL=1` mode sends.
* **Release tarball, no build.** `ojs-<version>.tar.gz` ships vendor and
  the compiled assets.
* **The CLI tools run on the embedded PHP:**
  `docker compose exec ephpm ephpm php tools/upgrade.php check`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # the installer; database fields are prefilled from compose.yml
```

`PKP_BASE_URL` must be the URL users open. After installing, create a
journal under Administration > Hosted Journals.

```bash
docker compose exec ephpm ephpm php tools/upgrade.php check
docker compose exec ephpm ephpm php tools/runScheduledTasks.php    # what the cron service does hourly
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release tarball onto the `ephpm/ephpm` image |
| `front.php` | Supplies `PATH_INFO` and runs `index.php` |
| `ephpm.toml` | Server config (app-root docroot, fallback to the front controller, blocked paths, limits) |
| `entrypoint.sh` | Seeds `public/`, writes `config.inc.php` once, waits for the DB, starts `ephpm serve` (or the cron loop) |
| `compose.yml` | ePHPm + cron + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/ojs/test.sh`) |

## Configuration notes

* `/var/www/files` (submission files, `files_dir`), `public/` (journal
  logos, public uploads) and `/var/www/config` (`config.inc.php`) are
  volumes. The official image keeps the config inside the app directory;
  here it is in a volume so the installer's edits survive a rebuild.
* `[server.security] blocked_paths` keeps PHP from executing under
  `public/` (the official `php_flag engine off`) and hides the config,
  cache and `.htaccess` files.
* Uploads: `[server.request] max_body_size` is 100 MiB with matching ini
  overrides; `[server.timeouts] request = 300` for imports.
* OJS 3.5 runs its job queue on web requests by default
  (`[queues] job_runner = On`); for a dedicated worker run
  `docker compose exec ephpm ephpm php lib/pkp/tools/jobs.php work`.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and an `https://` `PKP_BASE_URL`; OJS honours `X-Forwarded-Proto` via
  `[general] trust_x_forwarded_for`-style settings in `config.inc.php`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default). After
  installing a plugin from the admin UI run
  `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* `imagick`, `antiword`, `poppler-utils` and `ghostscript` (full-text
  indexing of office/PDF files in the official image) are not available;
  GD is. Searching still works on metadata.
* The image has no `sendmail`; OJS's default mailer logs `Connection to
  "process /usr/sbin/sendmail -bs" has been closed unexpectedly` (e.g. the
  installer's welcome mail). Configure SMTP (`[email] smtp = On` and the
  `smtp_*` keys in `config.inc.php`) for real mail.
* `error_reporting` is `E_ALL & ~E_DEPRECATED` in `ephpm.toml`: OJS 3.5
  on PHP 8.4 otherwise logs dozens of deprecation notices per request.
* `session_check_ip` is left at OJS's default (`On`); behind a proxy set
  `PKP_SESSION_CHECK_IP=Off` or configure `trusted_proxies`.
