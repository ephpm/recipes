# Dolibarr ERP/CRM on ePHPm

| | |
|---|---|
| App | [Dolibarr](https://www.dolibarr.org) 24.0.2 (`DOLI_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.4` |
| Replaces | the official `dolibarr/dolibarr` image (php-apache + the `mysql` client its entrypoint loads the schema with) and its cron container |
| Default stack | `compose.yml` — ePHPm + cron (same image) + MariaDB 11 |
| Single container | not offered — not attempted on ePHPm's embedded database |
| Status | tested 2026-10-11 on v0.11.3-php8.4 (`compose.yml`): image build, schema + default data + super admin loaded on first start, login through the login form, a user created through the "New user" form and read back on its card and in the user list, the cron service running a scheduled job with the cron key |

## What changes versus the official image

* **One process serves Dolibarr.** ePHPm serves `htdocs/` and runs PHP;
  Dolibarr's pages are plain PHP files, so `[server] fallback` only maps
  unknown paths to `index.php`. `conf/` and `install/` are refused with
  `[server.security] blocked_paths`.
* **Same environment variables** as `dolibarr/dolibarr`: `DOLI_DB_HOST`,
  `DOLI_DB_HOST_PORT`, `DOLI_DB_NAME`, `DOLI_DB_USER`, `DOLI_DB_PASSWORD`,
  `DOLI_URL_ROOT`, `DOLI_ADMIN_LOGIN`, `DOLI_ADMIN_PASSWORD`,
  `DOLI_COMPANY_NAME`, `DOLI_COMPANY_COUNTRYCODE`, `DOLI_ENABLE_MODULES`,
  `DOLI_INSTANCE_UNIQUE_ID`, `DOLI_CRON_KEY`, `DOLI_AUTH`, `DOLI_PROD`.
  `conf/conf.php` is written from them on each new container, as the
  official entrypoint does.
* **Automatic install without a `mysql` client.** The official entrypoint
  (`DOLI_INSTALL_AUTO=1`) pipes `install/mysql/{tables,functions,data}/*.sql`
  through the `mysql` client, inserts the super admin and runs
  `docker-init.php`. Here `init-db.php` loads the same files in the same
  order over mysqli and `init-modules.php` is that `docker-init.php` (plus
  the Cron module and `CRON_KEY`, so the cron service has jobs to run).
  One difference: a failing statement does not abandon the rest of its
  file, which is what Dolibarr's own web installer does. Three failures
  are expected and harmless — `llx_c_regions.key.sql` says so itself
  ("Duplicate key name 'uk_code_region' … to ignore"), and the upstream
  region/department data carries one duplicate entry each.
* **Stable secrets.** `DOLI_INSTANCE_UNIQUE_ID` (Dolibarr derives
  encryption keys from it) and `DOLI_CRON_KEY` are generated once into the
  documents volume when not given; the official image falls back to a
  fixed `myinstanceuniquekey` instead.
* **Cron as a service.** `cron` runs `scripts/cron/cron_run_jobs.php
  <key> firstadmin` every 5 minutes on the same image.

## Run

```bash
DOLI_ADMIN_PASSWORD=change-me docker compose up -d
open http://localhost:8080          # log in as admin / DOLI_ADMIN_PASSWORD
```

`DOLI_URL_ROOT` must be the URL users open (default
`http://localhost:8080`; with `EPHPM_PORT` set it to match). After the
first login Dolibarr opens its setup page (company, modules) — the same as
the official image.

```bash
docker compose exec ephpm sh -c 'ephpm php /var/www/dolibarr/scripts/cron/cron_run_jobs.php "$(cat /var/www/documents/.ephpm-cron-key)" firstadmin'   # run the jobs now
docker compose logs cron
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Fetches the release source (`htdocs/`, `scripts/`) onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, blocked paths, upload limits) |
| `entrypoint.sh` | Writes `conf/conf.php`, waits for the DB, loads the schema once, locks the installer, starts `ephpm serve` (or the cron loop) |
| `init-db.php` | Loads the schema, default data and super admin over mysqli |
| `init-modules.php` | Enables the User and Cron modules, applies the company/module variables |
| `compose.yml` | ePHPm + cron + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/dolibarr/test.sh`) |

## Configuration notes

* Volumes: `documents` (`/var/www/documents`: uploaded files, generated
  PDFs, `install.lock`, the generated instance id and cron key) and
  `custom` (`htdocs/custom`: external modules).
* Uploads: `[server.request] max_body_size` and the ini limits are 64 MiB,
  `memory_limit` 256M — the official image's defaults.
* Mail: the image has no `sendmail`; configure SMTP in Setup → E-mails.
* Behind a TLS-terminating proxy set `DOLI_URL_ROOT` to the public
  `https://` URL and `[server.security] trusted_proxies`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After installing an external module into `custom/` run
  `docker compose exec ephpm ephpm cache reset` or restart the container.

## Known limitations

* **Upgrades are not automated.** The official entrypoint runs
  `install/upgrade.php` / `upgrade2.php` / `step5.php` when the files are
  newer than the database (after a `mysqldump` backup); this recipe does
  not. After changing `DOLI_VERSION`, back up the database and run those
  scripts with `docker compose exec ephpm ephpm php …` from `htdocs/install`
  (and remove `install.lock`/create `upgrade.unlock` as Dolibarr asks).
* **The REST API needs PATH_INFO** (`/api/index.php/<resource>`), which
  ePHPm does not provide ([issues/espocrm.md](../../issues/espocrm.md)).
  Not exercised; expect the API module's URLs to fail without a front
  controller shim.
* `ext-gd` without JPEG/FreeType (`issues/koel.md`): JPEG logo/photo
  thumbnails and charts that need TrueType fonts may not render. Not
  exercised. `ext-imap` (e-mail collector) and `ext-ldap` are not in the
  ePHPm build.
