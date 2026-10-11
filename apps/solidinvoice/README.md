# SolidInvoice on ePHPm

| | |
|---|---|
| App | [SolidInvoice](https://solidinvoice.co) 3.0.1 (`SOLIDINVOICE_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.4` (SolidInvoice 3 targets PHP 8.4) |
| Replaces | the official `solidinvoice/solidinvoice` image (a static FrankenPHP binary with Caddy) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not available — Doctrine's MySQL DDL fails on ePHPm's embedded database ([issues/shlink.md](../../issues/shlink.md)); SolidInvoice's own SQLite mode is untested here |
| Status | tested 2026-10-11 on v0.11.3-php8.4: install (schema + admin) by the entrypoint, `solidinvoice:is-installed` confirms it, login through the form, first company created through the onboarding form and read back on the dashboard, clients page served, `about` on the console |

## What changes versus the official image

* **Per-request PHP instead of the FrankenPHP binary.** The official image
  is a single Go/PHP executable (`solidinvoice run`) embedding Caddy and the
  app. This recipe serves the release tarball's `public/index.php` in
  ePHPm's per-request mode; Caddy's `php_server` for `public/` is
  `[server] fallback` in `ephpm.toml`.
* **Same config directory.** `SOLIDINVOICE_CONFIG_DIR=/etc/solidinvoice` (a
  volume) holds the secrets vault SolidInvoice writes during installation —
  database URL, app secret, installed flag, application URL — exactly as
  in the official image, with `SOLIDINVOICE_ENV=prod`.
* **Installation from the environment.** The official image expects you to
  complete the web installer at `/install`. Here `entrypoint.sh` runs the
  same installer non-interactively (`bin/console app:install`) on first
  start when `ADMIN_EMAIL` + `ADMIN_PASSWORD` are set, using the
  `DATABASE_*` variables in `compose.yml`; leave them unset and the web
  installer is used instead. Later starts run pending migrations.
  SolidInvoice 3.0.1's `app:install` does not run its own schema step on
  the CLI (its installation steps are generators the command never
  iterates — see the SolidInvoice section of [UPSTREAM.md](../../UPSTREAM.md)),
  so the entrypoint builds the schema the way the web installer does
  (`doctrine:schema:update` + marking every migration as executed) between
  two `app:install` runs.
* **Release tarball, no build.** `SolidInvoice-<version>.tar.gz` ships
  vendor and the compiled `public/static` assets.
* **The console runs on the embedded PHP:**
  `docker compose exec ephpm solidinvoice app:install --help`.

## Run

```bash
ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=change-me docker compose up -d
open http://localhost:8080
```

`APPLICATION_URL` (default `http://localhost:8080`) is stored at install
time; change it later with
`docker compose exec ephpm solidinvoice secrets:set SOLIDINVOICE_APPLICATION_URL`.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release tarball onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, upload limits, timeouts) |
| `entrypoint.sh` | Waits for the DB, runs `app:install` once (or migrations), warms the cache, starts `ephpm serve` |
| `solidinvoice` | `bin/console` wrapper over the embedded PHP |
| `compose.yml` | ePHPm + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/solidinvoice/test.sh`) |

## Configuration notes

* `/etc/solidinvoice` (vault + keys) is the only state outside the
  database; back it up with the database.
* `[server.request] max_body_size` is 64 MiB (logo and attachment uploads);
  `[server.timeouts] request = 300` covers PDF generation.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and an `https://` application URL.
* Mail: configure SMTP in Settings after login (SolidInvoice stores it in
  the database); the image has no `sendmail`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default). After
  changing PHP files run `docker compose exec ephpm ephpm cache reset` or
  restart the container.

## Known limitations

* The MCP server and OAuth endpoints SolidInvoice 3 ships are untested
  here; the smoke test covers install, login, company creation and the
  client list. Creating clients/invoices goes through Symfony UX Live
  Components (browser-driven) and was not scripted.
* No scheduler service is shipped. The installer tells you to run
  `console cron:run` every minute, but on 3.0.1 that command fails with
  "There are no commands defined in the "schedule" namespace" (an
  application-side problem, not ePHPm's), so recurring invoices and other
  scheduled work are not exercised here.
* `imagick` is not available; GD is.
