# Drupal on ePHPm

| | |
|---|---|
| App | [Drupal](https://www.drupal.org) 11.4.9 (`drupal/recommended-project`, `DRUPAL_VERSION` build arg) + Drush 13 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the official `drupal` image) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | none — not attempted (Drupal's SQLite driver would be the natural candidate) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: `drush site:install` + page/article recipes on first start, log in through `/user/login`, create an article through `/node/add/article` and read it back (clean URL and `/index.php/...`), settings/YAML files 403, Drush on the embedded PHP |

## What changes versus the official image

* **One process.** ePHPm serves `web/`; the `web/.htaccess` front-controller
  rule is `[server] fallback` (clean URLs, and image-style derivatives that
  do not exist yet are generated through `index.php`). `vendor/` and the
  rest of the project sit above the web root.
* **Same project layout.** Built like the official image —
  `composer create-project drupal/recommended-project` into `/opt/drupal` —
  plus `drush/drush`. `web/sites` (settings.php, public files) and
  `/opt/drupal/private` (private files, outside the web root) are volumes.
* **Unattended install.** The official image always starts at the web
  installer. Here, with `DRUPAL_ADMIN_PASSWORD` and the `DRUPAL_DB_*`
  variables set, the first start runs `drush site:install`
  (`DRUPAL_PROFILE`, default `standard`) and then applies
  `DRUPAL_RECIPES` (default: the core page and article content-type
  recipes — Drupal 11.4's `standard` profile no longer creates content
  types itself). Later starts run `drush updatedb`. Leave
  `DRUPAL_ADMIN_PASSWORD` empty to use `/core/install.php` instead.
* **Drush on the embedded PHP.** `vendor/bin` is on `PATH`, and `php` /
  `DRUSH_PHP` point at an `ephpm php` shim, because Drush re-invokes PHP for
  batches and sub-processes and `PHP_BINARY` is `ephpm` here (ephpm#558).
* **What `web/.htaccess` denies** that matters is in `[server.security]
  blocked_paths`: `sites/*/settings*.php`, `sites/*/*.yml`, private and
  compiled-PHP directories under `files/`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 ... to change
```

Log in at `/user/login` with `DRUPAL_ADMIN_USER` / `DRUPAL_ADMIN_PASSWORD`
(`admin` / `drupal-admin-password` by default — set your own in a `.env`
file before the first start).

```bash
docker compose exec ephpm drush status
docker compose exec ephpm drush cache:rebuild
docker compose exec ephpm drush recipe core/recipes/standard_responsive_images
docker compose exec ephpm drush config:export     # into sites/default/files/config_* by default
docker compose restart ephpm                      # after changing PHP code in the container
```

Modules and themes are added the Composer way — in your own project's
`composer.json`, then rebuild the image (`composer require drupal/<module>`
in the Dockerfile's first stage), then `drush pm:install <module>`.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | `composer create-project drupal/recommended-project` + Drush, onto `ephpm/ephpm` |
| `ephpm.toml` | Server config: `web/` root, front-controller fallback, `.htaccess` denials, 64 MiB uploads |
| `entrypoint.sh` | Seeds `web/sites`, waits for the DB, `drush site:install` + recipes (or `updatedb`), `ephpm serve` |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/drupal/test.sh`) |

## Configuration notes

* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  **and** `$settings['reverse_proxy']` / `$settings['reverse_proxy_addresses']`
  in `settings.php`; set `$settings['trusted_host_patterns']` for your
  domain (Drupal's status report warns until you do).
* Cron: `automated_cron` (on in `standard`) runs it on page views; for a
  real schedule run `drush cron` from a host cron or an extra service.
* OPcache runs with timestamp validation off (`ephpm serve` default). The
  code lives in the image, so this only matters if you edit PHP inside a
  running container — then `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`). Twig templates compile to
  new file names and are unaffected.

## Known limitations

* `drush sql:*` commands (`sql:cli`, `sql:dump`, `sql:query`) shell out to
  the `mysql` client, which is not in the image. Add `mariadb-client` in the
  Dockerfile if you need them.
* GD in ePHPm has no JPEG/WebP/FreeType: image styles (thumbnails) work for
  PNG/GIF uploads only; JPEG uploads are stored but cannot be resized.
