# InvoicePlane on ePHPm

| | |
|---|---|
| App | [InvoicePlane](https://invoiceplane.com) 1.7.2 (`IP_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm (the upstream `docker-compose.yml`), or the `php:8.2-apache` image the upstream `Containerfile` builds |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not available — the app's upgrade migrations use `ALTER TABLE … MODIFY/CHANGE/AFTER`, which the embedded database rejects ([issues/invoiceplane.md](../../issues/invoiceplane.md)) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: schema + 44 migrations + default admin created by the entrypoint, login through the web form, dashboard, a client created through the HTML form and read back from the client list |

## What changes versus the official image

* **One process.** ePHPm serves `assets/` and runs PHP; the upstream nginx
  `try_files $uri $uri/ /index.php$is_args$args` becomes `[server] fallback`
  in `ephpm.toml`, so `REMOVE_INDEXPHP=true` clean URLs work out of the box.
* **Same environment variables as the official container**
  ([`CONTAINER_DEPLOYMENT.md`](https://github.com/InvoicePlane/InvoicePlane/blob/v1.7.2/.github/docs/CONTAINER_DEPLOYMENT.md)):
  `IP_URL`, `DB_HOSTNAME`, `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE`,
  `DB_PORT`, `ENCRYPTION_KEY`, `DEFAULT_ADMIN_EMAIL`,
  `DEFAULT_ADMIN_PASSWORD`, `DEFAULT_ADMIN_NAME`, `DEFAULT_LANGUAGE`,
  `COOKIE_SECURE`, the `SESS_*`, `CUSTOM_*TEMPLATES*`, `PASSWORD_RESET_*`,
  `LEGACY_CALCULATION`, `ENABLE_INVOICE_DELETION`, `DISABLE_READ_ONLY`,
  `SUMEX_*` and `SEC_STRIP_EXIF_FROM_IMAGES` knobs. `entrypoint.sh` writes
  `ipconfig.php` from them on every start, with `DISABLE_SETUP=true` and
  `SETUP_COMPLETED=true` like the official entrypoint, so the web setup
  wizard is never exposed.
* **One difference:** `ENCRYPTION_KEY` is optional here. When unset, a key
  is generated once and kept in the `storage` volume
  (`storage/ephpm-encryption-key`); the official image refuses to start
  without the variable. Set it explicitly if you want the key outside the
  volume.
* **Release zip, no build.** The image downloads the `v1.7.2.zip` release
  (vendor and compiled assets included); nothing runs Composer or Yarn.
* **The CLI runs on the embedded PHP:**
  `docker compose exec ephpm ephpm php index.php setup/cli/migrate`.

## Run

```bash
DEFAULT_ADMIN_PASSWORD=change-me docker compose up -d     # or: podman compose
open http://localhost:8080     # log in as admin@localhost / change-me
```

Leave `DEFAULT_ADMIN_PASSWORD` unset and a random one is printed to the
container log on first start (`docker compose logs ephpm`). `IP_URL` must be
the URL users actually open (`EPHPM_PORT=8090 IP_URL=http://localhost:8090 …`);
InvoicePlane builds links, redirects and cookies from it.

```bash
docker compose exec ephpm ephpm php index.php setup/cli/migrate   # after an image upgrade
docker compose logs ephpm                                        # PHP errors and the app log
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release zip onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, blocked paths, upload limits, timeouts) |
| `entrypoint.sh` | Writes `ipconfig.php` from the environment, waits for the DB, migrates, creates the admin, starts `ephpm serve` |
| `compose.yml` | ePHPm + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/invoiceplane/test.sh`) |

## Configuration notes

* `uploads/` (customer files, logos, mPDF temp) and `storage/` (sessions,
  cache, logs, the generated encryption key) are volumes.
  `[server.security] blocked_paths` keeps `application/`, `vendor/`,
  `storage/`, `ipconfig.php` and PHP files under `uploads/` off the web —
  what the shipped `.htaccess` files and the upstream nginx config deny.
* Uploads: `[server.request] max_body_size` (64 MiB) and the
  `upload_max_filesize` / `post_max_size` ini overrides move together.
* `[server.timeouts] request = 600` and `max_execution_time = 300` mirror
  the upstream nginx `fastcgi_read_timeout 600` — PDF generation with mPDF
  can take a while on large invoices.
* Sessions use CodeIgniter's `files` driver under `storage/framework/sessions`
  (the app's default; `SESS_SAVE_PATH` overrides it). The native `ephpm`
  session handler is not used: CodeIgniter 3 runs its own session layer.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`,
  an `https://` `IP_URL` and `COOKIE_SECURE=true`.
* Mail is configured in the app (Settings > Email) with its own SMTP
  settings; the image has no `sendmail`, so use SMTP.
* OPcache runs with timestamp validation off (ePHPm's `serve` default). After
  changing PHP files (custom templates) run
  `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).
* Cron: InvoicePlane's recurring invoices run on a cron hitting
  `/invoices/cron/recur?cron_key=<key>` (Settings > General). Add a host
  cron entry with `curl` for that URL.

## Known limitations

* No single-container variant: the upgrade migrations use MySQL-only
  `ALTER TABLE` syntax (`MODIFY`, `CHANGE`, `ADD … AFTER col`,
  `ADD PRIMARY KEY`) that the embedded database (Turso engine behind the
  MySQL listener) rejects. Details and a minimal repro in
  [issues/invoiceplane.md](../../issues/invoiceplane.md).
* The upstream dev image installs `imagick` and `imap`; neither is in the
  ePHPm build. InvoicePlane only needs GD (compiled in); nothing in the app
  uses IMAP.
* `LEGACY_CALCULATION` defaults to `false` here, as in the official
  container (not the `true` of `ipconfig.php.example`).
