# InvoiceShelf on ePHPm

| | |
|---|---|
| App | [InvoiceShelf](https://invoiceshelf.com) 2.4.6 (`INVOICESHELF_VERSION` build arg) — Laravel |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `invoiceshelf/invoiceshelf` image (nginx + php-fpm + cron) |
| Default stack | `compose.yml` — ePHPm + a `scheduler` service on the same image + MariaDB 11 |
| Single container | not offered (InvoiceShelf also supports SQLite natively; not packaged here) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: migrate + seed and unattended wizard on first start, web (Sanctum SPA) login, token API login, create a customer and an invoice and read them back, mark it sent, the scheduler's `check:invoices:status` (spawned as a child `php artisan`) flags it overdue |

## What changes versus the official image

* **One process serves the app.** ePHPm serves `public/` with the Laravel
  front-controller fallback; no nginx, no php-fpm.
* **Built from the release zip** (`vendor/` and the built front end
  included) — no Composer or Node stage.
* **The installation wizard runs unattended** when
  `INVOICESHELF_ADMIN_PASSWORD` is set: the entrypoint runs the wizard's
  database step itself (`artisan migrate --seed`, which creates a placeholder
  admin `admin@invoiceshelf.com` and company "xyz"), then `setup.php` turns
  that account and company into the configured ones and marks the wizard
  complete. Company address, currency, language and timezone keep the seeded
  defaults; change them in Settings. Without a password, the wizard opens in
  the browser after the database step.
* **Configuration comes from the environment** (`DB_*`, `APP_URL`,
  `SANCTUM_STATEFUL_DOMAINS`, `SESSION_DOMAIN`, `MAIL_*`, …) instead of the
  `.env` the wizard writes; `APP_KEY` is generated once into `storage/.env`
  (the `storage` volume).
* **Scheduler as a service** (`schedule:work`). `ENV PHP_BINARY` points
  Laravel at the `php` → `ephpm php` shim, so scheduled commands (spawned as
  child processes) really run (`issues/pterodactyl.md`); `test.sh` checks it.

## Environment

| Variable | Default (compose) | Meaning |
|---|---|---|
| `APP_URL` | `http://localhost:8080` | public URL (links in PDFs and e-mails) |
| `SANCTUM_STATEFUL_DOMAINS` | `localhost:8080` | `host:port` the browser uses — the SPA login fails with 401s otherwise |
| `SESSION_DOMAIN` | `localhost` | cookie domain (the host without port) |
| `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` | MariaDB `db` | database |
| `INVOICESHELF_ADMIN_EMAIL` / `_PASSWORD` / `_NAME`, `INVOICESHELF_COMPANY_NAME` | `admin@example.com` / — / `Admin` / `My Company` | first start only (recipe-specific) |

## Run

```bash
INVOICESHELF_ADMIN_PASSWORD='something-long' docker compose up -d   # or: podman compose up -d
open http://localhost:8080
# another port: EPHPM_PORT=8090 APP_URL=http://localhost:8090 SANCTUM_STATEFUL_DOMAINS=localhost:8090 docker compose up -d
```

```bash
docker compose exec ephpm php artisan migrate:status        # `php` is a shim for `ephpm php`
docker compose exec scheduler php artisan schedule:list
docker compose logs ephpm scheduler
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Release zip onto `ephpm/ephpm`, `php` shim, `PHP_BINARY` |
| `ephpm.toml` | Server config (`public/` root, front-controller fallback) |
| `entrypoint.sh` | Seeds `storage/` and `.env`, `APP_KEY`, waits for the DB, migrates (seeds a fresh DB), runs `setup.php`, starts `ephpm serve` — or the scheduler |
| `setup.php` | Finishes the installation wizard (admin, company, `profile_complete`) |
| `php` | `php` on PATH → `ephpm php` |
| `compose.yml` | ePHPm + scheduler + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/invoiceshelf/test.sh`) |

## Configuration notes

* OPcache runs with timestamp validation off (`ephpm serve` default):
  `docker compose restart ephpm` after changing PHP files (modules).
* Behind a TLS-terminating proxy set `APP_URL`, `SANCTUM_STATEFUL_DOMAINS`
  and `SESSION_DOMAIN` to the public host, `SESSION_SECURE_COOKIE=true`, and
  `[server.security] trusted_proxies`.
* Mail: set `MAIL_MAILER=smtp` and `MAIL_*`; the image has no `sendmail`.

## Known limitations

* **Company logos and expense receipts: PNG/GIF only** if they are resized —
  ePHPm's GD has no JPEG/WebP (`issues/koel.md`); not exercised by `test.sh`.
* PDF generation (dompdf, the default) is not exercised by `test.sh`.
