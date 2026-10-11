# Mautic on ePHPm

| | |
|---|---|
| App | [Mautic](https://mautic.org) 7.2.1 (`mautic/recommended-project`, `MAUTIC_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.4` |
| Replaces | the official `mautic/mautic` image in its three roles — `mautic_web` (php-apache / php-fpm), `mautic_cron` and `mautic_worker` (supervisord + messenger consumers) |
| Default stack | `compose.yml` — ePHPm (web) + cron + worker (same image) + MariaDB 11 |
| Single container | not offered — Mautic is MySQL/MariaDB only and its Doctrine migrations use MySQL DDL the embedded database rejects (same class of gap as [issues/shlink.md](../../issues/shlink.md)) |
| Status | tested 2026-10-11 on v0.11.3-php8.4 (`compose.yml`): image build (Composer + npm + Sass/AssetMapper build), `mautic:install` (schema + admin) on first start, login through the login form, create a contact through the "New contact" form and read it back on its page and in the contact search, `--version` on the console; cron and worker services start once the install is done |

## What changes versus the official image

* **One server process for the web role.** ePHPm serves `docroot/` and runs
  PHP; the rewrite in `docroot/.htaccess` (everything not on disk →
  `index.php`) is `[server] fallback` in `ephpm.toml`, and PHP under
  `media/` is refused with `[server.security] blocked_paths`.
* **Same three roles, same image.** `cron` runs the official cron role's
  jobs (`mautic:segments:update`, `mautic:campaigns:update`,
  `mautic:campaigns:trigger`) every 15 minutes in a shell loop instead of
  cron; `worker` runs `messenger:consume email hit failed` (the
  official worker role's consumers). Both wait for the web container to
  finish installing.
* **Same environment variables** as `mautic/mautic`: `MAUTIC_DB_HOST`,
  `MAUTIC_DB_PORT`, `MAUTIC_DB_DATABASE`, `MAUTIC_DB_USER`,
  `MAUTIC_DB_PASSWORD`, `MAUTIC_MESSENGER_DSN_EMAIL`,
  `MAUTIC_MESSENGER_DSN_HIT`.
* **Unattended install.** With `MAUTIC_ADMIN_EMAIL` and
  `MAUTIC_ADMIN_PASSWORD` set, the entrypoint runs `mautic:install` on first
  start (`MAUTIC_SITE_URL`, `MAUTIC_ADMIN_USERNAME` — default `admin` —,
  `MAUTIC_ADMIN_FIRSTNAME`, `MAUTIC_ADMIN_LASTNAME`). Leave them unset to
  use the web installer at `/installer`. Later starts run
  `doctrine:migrations:migrate`.
* **Built like the official image.** Mautic ships as a Composer project:
  the Dockerfile runs `composer create-project`, then the npm half of the
  Composer scripts in a Node stage, then the PHP half
  (`mautic:assets:generate`, `assets:install`, `sass:build`,
  `asset-map:compile`) on the embedded PHP.
* **The console runs on the embedded PHP** through the `mautic` wrapper
  (`ephpm php bin/console`).

## Run

```bash
MAUTIC_ADMIN_EMAIL=you@example.com MAUTIC_ADMIN_PASSWORD=change-me docker compose up -d
open http://localhost:8080       # log in as admin / change-me
```

`MAUTIC_SITE_URL` must be the URL users open (default
`http://localhost:8080`; with `EPHPM_PORT` set it to match). The first
start installs the schema, which takes a minute; the log says
`Mautic is ready` when it is done.

```bash
docker compose exec ephpm mautic --version
docker compose exec ephpm mautic mautic:segments:update
docker compose exec ephpm ephpm php bin/console cache:clear   # the same, without the wrapper
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Composer create-project + npm + asset build onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, blocked paths, upload limits, timeouts) |
| `entrypoint.sh` | Seeds volumes, waits for the DB, installs or migrates, starts `ephpm serve` (or the cron/worker command once installed) |
| `mautic` | `bin/console` wrapper over the embedded PHP |
| `compose.yml` | web + cron + worker + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/mautic/test.sh`) |

## Configuration notes

* `config/` (`local.php` — database settings and the secret key written by
  the installer), `var/logs` and `docroot/media/{files,images}` are volumes.
* Uploads: `[server.request] max_body_size` is 512 MiB with matching ini
  overrides, `[server.timeouts] request = 300` and `memory_limit = 512M`,
  as in the official image's PHP settings.
* Messenger transports default to `doctrine://default` (the database), as
  in the official example; point `MAUTIC_MESSENGER_DSN_*` at a real broker
  (Redis/RabbitMQ) if you have one.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After installing a plugin or theme run
  `docker compose exec ephpm ephpm cache reset` (or restart the container).
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and an `https://` `MAUTIC_SITE_URL`.

## Known limitations

* The image has no `sendmail`; configure an SMTP/API mailer DSN in
  Configuration → Email Settings.
* `checkdnsrr()` / `dns_get_record()` hang in ePHPm v0.11.3
  ([issues/freshrss.md](../../issues/freshrss.md)); any Mautic feature or
  plugin that validates e-mail domains over DNS would hang a request until
  `[server.timeouts] request` fires. The smoke test creates its contact
  without an e-mail address and did not exercise this.
* `imagick` is not available; GD is (without JPEG/WebP/FreeType in the
  SDK build), so image resizing of uploaded JPEGs in the asset manager may
  not work. Not tested.
* Email sending, campaigns with real contacts, tracking pixels and the
  form/landing-page builders were not exercised by the smoke test.
