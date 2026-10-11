# GLPI on ePHPm

| | |
|---|---|
| App | [GLPI](https://glpi-project.org) 12.0.0 (`GLPI_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php + supervisord (running the GLPI cron) — the official `glpi/glpi` image |
| Default stack | `compose.yml` — ePHPm + cron sidecar (same image) + MariaDB 11 |
| Single container | none — GLPI supports only MySQL/MariaDB; the embedded database variant was not attempted |
| Status | tested 2026-10-11 on v0.11.3-php8.5: `bin/console database:install` on first start, log in as glpi/glpi, create a computer through the asset form (a `/front/*.php` URL routed by `public/index.php`) and read it back, code/config outside `public/` answers 404, `bin/console db:check`, the cron sidecar runs `front/cron.php` |

## What changes versus the official image

* **One web process.** ePHPm serves `public/` (the web root GLPI requires
  since 10.0.7). The official vhost's rule — anything that is not a file
  goes to `index.php` — is `[server] fallback`; GLPI's router then serves
  the legacy `/front/*.php` and `/ajax/*.php` scripts that live outside
  `public/`. Nothing else outside `public/` is reachable (`/config/...`,
  `/vendor/...`, `/files/...` answer the router's 404).
* **Same variables and layout as `glpi/glpi`.** `GLPI_DB_HOST`,
  `GLPI_DB_PORT`, `GLPI_DB_NAME`, `GLPI_DB_USER`, `GLPI_DB_PASSWORD`,
  `GLPI_SKIP_AUTOINSTALL`, `GLPI_SKIP_AUTOUPDATE`; configuration, files,
  logs and marketplace plugins live in the `/var/glpi` volume
  (`GLPI_CONFIG_DIR`, `GLPI_VAR_DIR`, `GLPI_LOG_DIR`,
  `GLPI_MARKETPLACE_DIR`). On the first start the database is installed with
  `bin/console database:install`; on later starts `database:update` runs, as
  the official entrypoint does.
* **Runs as `www-data`**, like the official image — GLPI's console and
  `front/cron.php` refuse to run as root.
* **The cron is a sidecar.** The official image's `glpi-cron` supervisord
  program (`front/cron.php` every 60 s) is the `cron` service: the same
  image started with `cron`, waiting until the server has installed or
  updated the database.
* The official image's `conf.d/glpi.ini` (session cookie flags, GC
  lifetime, 20 MiB uploads, `max_input_vars = 5000`) is in `ini_overrides`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 ... to change
```

The first start takes a minute (schema install). Log in as `glpi` / `glpi`
and change the passwords of the default accounts (`glpi`, `tech`,
`normal`, `post-only`) as GLPI's banner asks.

```bash
docker compose exec ephpm ephpm php bin/console db:check
docker compose exec ephpm ephpm php bin/console plugin:list
docker compose restart ephpm                     # after updating plugins (reloads PHP code)
```

`php` on PATH is a shim for `ephpm php`, so `php bin/console ...` works as in
GLPI's documentation.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Release tarball (vendor and built assets included) onto `ephpm/ephpm`, official env layout, `USER www-data` |
| `ephpm.toml` | Server config: `public/` web root, router fallback, `glpi.ini` settings |
| `entrypoint.sh` | Volume directories, wait for the DB, install/update, `ephpm serve`; `cron` mode for the sidecar |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/glpi/test.sh`) |

## Configuration notes

* Behind a TLS-terminating proxy set `[server.security] trusted_proxies` and
  the public URL in Setup → General → "URL of the application".
* Marketplace plugins install into `/var/glpi/marketplace`. OPcache runs
  with timestamp validation off (`ephpm serve` default): after **updating**
  a plugin, run `docker compose restart ephpm` (newly added files are picked
  up without it; `ephpm cache reset` is a no-op on a single node in v0.11.3,
  `issues/nextcloud.md`).
* Sessions are PHP file sessions in `/var/glpi/files/_sessions`, as
  upstream; nothing is moved to the KV store.

## Known limitations

* No single-container variant (see the table).
* The inventory agent endpoint and the REST/high-level APIs are served by
  the same router and were not exercised by the smoke test.
