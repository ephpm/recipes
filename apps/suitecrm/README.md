# SuiteCRM 7 on ePHPm

| | |
|---|---|
| App | [SuiteCRM](https://suitecrm.com) 7.15.2 (`SUITECRM_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.4` (SuiteCRM 7.15 targets PHP 8.1–8.4) |
| Replaces | Apache + mod_php (the usual SuiteCRM 7 host, e.g. the bitnami image) and the crontab line running `cron.php` |
| Default stack | `compose.yml` — ePHPm + a `cron` service on the same image + MariaDB 11 |
| Single container | not offered (not tried on ePHPm's embedded database; SuiteCRM's schema repair uses MySQL-only `ALTER TABLE` forms) |
| Status | tested 2026-10-11 on v0.11.3-php8.4: silent install on first start, login form, create an Account through the v4_1 REST API and read it back (API and DetailView), the cron service runs the schedulers, `.htaccess` deny rules 403 |

SuiteCRM **8** (`SuiteCRM-Core`, Symfony + Angular) is a different
application and is not covered here.

## What changes versus Apache

* **One process serves the app.** SuiteCRM 7's URLs name their scripts
  (`index.php?module=…`, `service/v4_1/rest.php`, `soap.php`), so there is no
  rewrite; `[server] fallback` ends in `=404`.
* **The `.htaccess` deny rules are `blocked_paths`.** The installer writes
  `RedirectMatch 403` rules into `.htaccess` (logs, `upload/`, cache
  diagnostics, blowfish keys, build files, and any `.php` under
  `soap|cache|xtemplate|data|examples|include|log4php|metadata|modules|vendor`).
  ePHPm ignores `.htaccess`; `ephpm.toml` lists the same paths (the `.tpl`/`.phar`
  variants are not repeated: templates hold no secrets). ePHPm globs
  match one path segment per `*`, so the "any depth" rule is spelled out for
  depths 1–6.
* **OPcache checks timestamps.** SuiteCRM writes PHP into `cache/` and
  `custom/` at runtime (Studio, Module Builder, Admin → Repair) and includes it
  right away, so `[php] opcache_validate_timestamps = true` (ePHPm's `serve`
  default is off).
* **Unattended install.** On the first start the entrypoint writes
  `config_si.php` from the `SUITECRM_*` variables and runs `install.php`'s
  SilentInstall path from the CLI (as upstream documents), then deletes
  `config_si.php`. No demo data.
* **The scheduler is a service.** The `cron` service runs `cron.php` every
  60 s on the same image and volume — the job of the
  `* * * * * php cron.php` crontab line. Everything in the container runs as
  root (ePHPm too), so the entrypoint adds `root` to
  `$sugar_config['cron']['allowed_cron_users']` in `config_override.php`
  (SuiteCRM refuses root by default because on a classic host files created
  by root's cron would not be writable by the web server user; here there is
  only one user).

## Environment

| Variable | Default (compose) | Meaning |
|---|---|---|
| `SUITECRM_SITE_URL` | `http://localhost:8080` | the URL users open SuiteCRM at (written to `config.php` at install) |
| `SUITECRM_DB_HOST` / `_PORT` / `_NAME` / `_USER` / `_PASSWORD` | `db` / `3306` / `suitecrm` / `suitecrm` / `suitecrm` | MySQL/MariaDB (install only; afterwards `config.php` holds them) |
| `SUITECRM_ADMIN_USER` / `SUITECRM_ADMIN_PASSWORD` | `admin` / `change-me-please` | the administrator (install only) |
| `SUITECRM_SYSTEM_NAME`, `SUITECRM_LANGUAGE`, `SUITECRM_CURRENCY_ISO4217`, `SUITECRM_CURRENCY_NAME`, `SUITECRM_CURRENCY_SYMBOL`, `SUITECRM_DATE_FORMAT`, `SUITECRM_TIME_FORMAT` | `SuiteCRM`, `en_us`, `USD`, `US Dollars`, `$`, `Y-m-d`, `H:i` | installer defaults |

The names are this recipe's; SuiteCRM 7 itself reads no environment.

## Run

```bash
SUITECRM_ADMIN_PASSWORD='something-long' docker compose up -d   # or: podman compose up -d
open http://localhost:8080      # EPHPM_PORT=8090 ... to change — then set
                                # SUITECRM_SITE_URL=http://localhost:8090 as well
```

The first start takes a minute or so while the installer creates the schema.

```bash
docker compose exec ephpm php -f cron.php                         # run the scheduler now
docker compose exec ephpm php -r 'require "suitecrm_version.php"; echo $suitecrm_version, "\n";'
docker compose logs ephpm cron                                    # PHP errors, ePHPm and scheduler logs
docker compose exec ephpm tail -f suitecrm.log                    # SuiteCRM's own log
```

`php` in the image is a shim for `ephpm php`.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Release zip (with `vendor/`) onto `ephpm/ephpm` |
| `ephpm.toml` | Server config (`=404` fallback, `.htaccess` deny rules, OPcache timestamps on) |
| `entrypoint.sh` | Seeds the volume, waits for the DB, silent install, `config_override.php`, starts `ephpm serve` — or the cron loop |
| `si-install.php` | Writes `config_si.php` and drives `install.php?goto=SilentInstall&cli=true` |
| `php` | `php` on PATH → `ephpm php` |
| `compose.yml` | The stack: ePHPm + cron + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/suitecrm/test.sh`) |

## Configuration notes

* **The whole SuiteCRM tree is the `app` volume**, seeded from the image on
  first start (SuiteCRM 7 writes into `custom/`, `modules/`, `cache/`,
  `upload/` and `config*.php`, as the bitnami image also persists). A newer
  image therefore does **not** upgrade an existing install: use SuiteCRM's
  Upgrade Wizard (Admin → Upgrade Wizard) with the upgrade package, as on any
  host.
* Uploads/imports: `max_body_size`, `upload_max_filesize` and
  `post_max_size` are 100 MiB; `max_execution_time` is 240 s.
* Behind a TLS-terminating proxy set `SUITECRM_SITE_URL` to the public
  `https://` URL before the first start (or `site_url` in `config.php`
  afterwards) and `[server.security] trusted_proxies`.
* Outbound e-mail: configure SMTP in Admin → Email Settings; the image has no
  `sendmail`.

## Known limitations

* **The V8 JSON:API (`/Api/V8/…`) does not work.** Apache rewrites it to
  `lib/API/public/index.php/<path>` and the Slim app routes on `PATH_INFO`,
  which ePHPm does not provide (`issues/espocrm.md`). The v4_1 REST API
  (`service/v4_1/rest.php`, used by the test) and SOAP are unaffected.
  The `Api/` and `ep/` rewrites from `.htaccess` are therefore not
  replicated; `index.php?entryPoint=…` works.
* PHP 8.4 prints deprecation notices from bundled libraries on the CLI; the
  cron loop filters them out. The web side logs nothing to pages
  (`display_errors = Off`).
* No single-container (embedded database) variant.
