# Krayin CRM on ePHPm

| | |
|---|---|
| App | [Krayin CRM](https://krayincrm.com) v2.2.6 (`KRAYIN_VERSION` build arg) — Laravel 12 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | a nginx/apache + php-fpm host and the cron entry for the Laravel scheduler (Krayin has no official production image) |
| Default stack | `compose.yml` — ePHPm + the scheduler (same image) + MariaDB 11 |
| Single container | not offered — Krayin supports MySQL/MariaDB only and its Laravel migrations add foreign keys with `ALTER TABLE … ADD CONSTRAINT`, which the embedded database rejects (see [issues/bookstack.md](../../issues/bookstack.md)); not attempted |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, unattended `krayin-crm:install` on first start with the admin account taken from `KRAYIN_ADMIN_*`, admin login through the login form, dashboard, a person created through the "Create person" form and read back on its page, `artisan migrate:status` on the embedded PHP |

## What changes versus a classic install

* **One process serves the CRM.** ePHPm is the HTTP server and the PHP
  runtime; `public/.htaccess` (everything that is not a file goes to
  `index.php`) is `[server] fallback` in `ephpm.toml`.
* **Built from the release tag.** The image runs `composer install --no-dev`
  in a `composer:2` stage (`--no-scripts`; `artisan package:discover` then
  runs on the embedded PHP). The admin bundle is committed upstream in
  `public/admin/build`, so there is no Node stage.
* **Unattended install on first start.** The entrypoint runs Krayin's own
  `artisan krayin-crm:install --skip-env-check --no-interaction` (APP_KEY,
  `migrate:fresh`, seed data, `vendor:publish`, `storage:link`, the admin
  user and the `storage/installed` marker), then sets the admin's
  e-mail/password from `KRAYIN_ADMIN_EMAIL` / `KRAYIN_ADMIN_PASSWORD`
  (and `KRAYIN_ADMIN_NAME`) when given. Later starts run
  `artisan migrate --force`. Because the installer starts with
  `migrate:fresh`, the entrypoint never runs it against a database that
  already holds a Krayin schema.
* **Two installer quirks handled in the entrypoint:** the installer reads
  its settings (`APP_ENV`, `DB_*`, …) straight from the `.env` *file* —
  and keeps any quotes as part of the value — so the container's
  variables are copied into `storage/.env` unquoted (values must not
  contain spaces); and it runs with `APP_ENV=local`, because in production
  Laravel refuses `migrate:fresh` under `--no-interaction` (switched back
  afterwards).
* **`.env` lives in the storage volume** (`/app/.env` points at it), so the
  generated `APP_KEY` survives container recreation. Every variable set in
  `compose.yml` still wins over the file for the running app.
* **Scheduler as a service.** `scheduler` runs `artisan schedule:run` every
  60 seconds on the same image; the `php` shim in the image lets
  scheduled `->command()` entries spawn `php artisan …` (see
  `issues/akaunting.md`).

## Run

```bash
KRAYIN_ADMIN_EMAIL=you@example.com KRAYIN_ADMIN_PASSWORD=change-me docker compose up -d
open http://localhost:8080/admin
```

Without `KRAYIN_ADMIN_*` the installer's default `admin@example.com` /
`admin123` is kept; change it. `APP_URL` must be the URL users open
(default `http://localhost:8080`; with `EPHPM_PORT` set it to match). The
first start takes a minute (schema + seed data); the log says
`Krayin is ready` when it is done.

```bash
docker compose exec ephpm ephpm php artisan migrate:status   # any artisan command
docker compose logs ephpm                                     # Laravel logs to stderr here
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Fetches the release source, `composer install`s it, copies it onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, blocked paths, upload limits, timeouts) |
| `entrypoint.sh` | Seeds the storage volume and `.env`, waits for the DB, installs or migrates, starts `ephpm serve` (or the given command once installed) |
| `compose.yml` | ePHPm + scheduler + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/krayin/test.sh`) |

## Configuration notes

* `storage` volume: uploaded files (served through `public/storage`),
  logs, `.env`, the installed marker. PHP is never executed from
  `/storage/` (`blocked_paths`).
* Cache and sessions use Laravel's `file` driver (Krayin's
  `.env.example`). Krayin does not bundle `predis` and the ePHPm build has
  no `phpredis`, so the Redis drivers are not available without adding
  `predis/predis`.
* Mail goes to the log (`MAIL_MAILER=log`) until you configure SMTP;
  inbound mail (IMAP / SendGrid webhook) was not tried — there is no
  `imap` extension in the ePHPm build.
* Behind a TLS-terminating proxy set `APP_URL` to the public `https://`
  URL and `[server.security] trusted_proxies` in `ephpm.toml`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After changing PHP files run `docker compose restart ephpm`
  (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* **ePHPm's GD build has no JPEG/WebP/FreeType support** (`issues/koel.md`);
  image processing of JPEG uploads (avatars) will not work. Not exercised.
* Leads, quotes, e-mail and web forms were not exercised by the smoke
  test; it covers install, login and the person (contact) form.
* `checkdnsrr()` / `dns_get_record()` hang in ePHPm v0.11.3
  ([issues/freshrss.md](../../issues/freshrss.md)); a validation rule that
  checks e-mail domains over DNS would hang its request.
