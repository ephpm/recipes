# Koillection on ePHPm

| | |
|---|---|
| App | [Koillection](https://koillection.github.io) 1.8.4 (`KOILLECTION_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` (Koillection 1.8 needs PHP 8.5) |
| Replaces | the official `koillection/koillection` image (FrankenPHP: Caddy + a persistent PHP worker) |
| Default stack | `compose.yml` — ePHPm + PostgreSQL 17 (Koillection's recommended database); `compose.mariadb.yml` for MariaDB |
| Single container | not available — Koillection needs PostgreSQL or MySQL, and Doctrine's MySQL DDL fails on ePHPm's embedded database ([issues/shlink.md](../../issues/shlink.md)) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (PostgreSQL 17 and MariaDB 11: first-connection admin creation, login, collections list, new-collection form, console) |

## What changes versus the official image

* **Per-request PHP instead of a FrankenPHP worker.** The official image
  boots the Symfony kernel once per worker; this one bootstraps it per
  request (`public/index.php`), the shape of a classic nginx + php-fpm
  deployment. Caddy's `handle /uploads/* { file_server }` + `php_server` is
  `[server] fallback` in `ephpm.toml`; the Caddyfile's security headers are
  `[server.response] headers`.
* **Same environment variables as `koillection/koillection`:** `DB_DRIVER`,
  `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_VERSION`,
  `APP_ENV`, `APP_DEBUG`, `APP_SECRET`, `JWT_*`, `CORS_ALLOW_ORIGIN`.
  `entrypoint.sh` writes them into `.env.local` exactly as the official
  entrypoint does (Koillection sets `runtime.dotenv_overload`, so the
  `.env` files — not the process environment — are what the app reads).
* **One difference:** `APP_SECRET` and `JWT_PASSPHRASE` are generated once
  into the `state` volume (`/var/lib/koillection`) when unset, and the JWT
  key pair lives there too. The official image regenerates them on every
  start, which invalidates remember-me cookies and API tokens.
* **Built from the release tag.** No dist archive exists; the build stage
  runs Composer, dumps the JS translation catalogues on the embedded PHP
  (`app:translations:dump`), and builds the frontend with Yarn — the
  official Dockerfile's steps, split over stages.
* **The console runs on the embedded PHP:**
  `docker compose exec ephpm koillection app:refresh-cached-values`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # the first visit creates the first user
```

```bash
docker compose -f compose.mariadb.yml up -d           # MariaDB instead of PostgreSQL
docker compose exec ephpm koillection app:refresh-cached-values
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Composer + translations + Yarn build stages from the release tag, copied onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, headers, upload limits) |
| `entrypoint.sh` | Seeds `public/uploads`, writes `.env.local`, waits for the DB, migrates, refreshes cached values, generates the JWT keys, starts `ephpm serve` |
| `koillection` | `bin/console` wrapper over the embedded PHP |
| `compose.yml`, `compose.mariadb.yml` | The two stacks |
| `test.sh` | The smoke test CI runs (`bash apps/koillection/test.sh`) |

## Configuration notes

* `public/uploads` (item/collection images) and `/var/lib/koillection`
  (secrets, JWT keys) are volumes. The official image mounts `/uploads`
  and symlinks it; here the directory itself is the volume.
* Uploads: `[server.request] max_body_size` is 100 MiB, with the official
  image's `upload_max_filesize=20M` / `post_max_size=100M` defaults
  (`UPLOAD_MAX_FILESIZE` is a build-time ini here, not an env var).
* APCu is not loaded (it is in ePHPm's extension catalog if you want it);
  Koillection falls back to its filesystem cache.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`;
  session cookies get the `Secure` flag from Symfony's `cookie_secure: auto`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default). After
  changing PHP files run `docker compose exec ephpm ephpm cache reset` or
  restart the container.

## Known limitations

* The official image bundles `curl-impersonate` (Firefox TLS fingerprint)
  for scraping item data from sites that block plain curl; this image uses
  PHP's stock curl, so some scrapers may be refused by those sites.
* `imagick` is not available; image handling uses GD (compiled in).
