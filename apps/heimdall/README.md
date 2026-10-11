# Heimdall on ePHPm

| | |
|---|---|
| App | [Heimdall](https://github.com/linuxserver/Heimdall) v2.8.3 (`HEIMDALL_VERSION` build arg) — Laravel 12, PHP ≥ 8.4 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `linuxserver/heimdall` image (nginx + php-fpm + s6) |
| Default stack | `compose.yml` — one container, SQLite in the data volume (upstream's default) |
| Single container | that is the default |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, migrations on start, dashboard, an application tile added through the "Add application" form (CSRF + session) and shown on the dashboard and the item list, `artisan migrate:status` on the embedded PHP |

## What changes versus the linuxserver image

* **One process.** ePHPm serves `public/` and runs PHP; the Laravel
  front-controller rule is `[server] fallback`.
* **The release source is used as is** — Heimdall commits `vendor/` and its
  built assets, so the image has no Composer or Node stage.
* **`/data` holds `.env` and `app.sqlite`** (`/app/.env` and
  `/app/database/app.sqlite` are symlinks into it), as the linuxserver
  image's `/config` does; `storage/` (uploaded icons, logs) is a second
  volume. `.env` is created from `.env.example` with a generated `APP_KEY`
  on first start.
* **Migrations run on start** (`artisan migrate --seed`, the same call
  Heimdall makes on its first request).
* **Settings:** anything in `.env` (`APP_URL`, `TRUSTED_HOSTS`,
  `TRUSTED_PROXIES`, `ALLOW_INTERNAL_REQUESTS`, `AUTH_ROLES_*`, …) can be
  set in the container environment instead, which Laravel prefers over
  `.env`.

## Run

```bash
docker compose up -d                # or: podman compose up -d
open http://localhost:8080          # EPHPM_PORT=8090 APP_URL=http://localhost:8090 docker compose up -d to change
```

Heimdall starts with a single user and no password; set one under
Settings → Users if the dashboard is reachable by others.

```bash
docker compose exec ephpm ephpm php artisan migrate:status
docker compose exec ephpm ephpm php artisan route:list
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release source (vendor and assets included), onto `ephpm/ephpm`; symlinks `.env`, the database and `public/storage` |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds `storage/`, creates `.env` + `APP_KEY`, migrates, starts `ephpm serve` |
| `compose.yml` | The single-container stack |
| `test.sh` | The smoke test CI runs (`bash apps/heimdall/test.sh`) |

## Configuration notes

* `APP_URL` must be the address the dashboard is opened at (links and asset
  URLs are built from it); behind a TLS proxy also set `FORCE_HTTPS=true`
  and `TRUSTED_PROXIES`.
* Website lookups and icon downloads for tiles are fetched server-side and
  refused for private addresses unless `ALLOW_INTERNAL_REQUESTS=true`
  (Heimdall's own SSRF guard).
* `.env.example` ships `APP_ENV=local`, so Heimdall logs at debug level;
  set `APP_ENV=production` in `compose.yml` for quieter logs.
* PHP code changes need a container restart (OPcache timestamp validation
  is off under `ephpm serve`; `ephpm cache reset` is a no-op on a single
  node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* Uploaded JPEG/WebP icons and backgrounds are stored and served as-is;
  nothing in Heimdall resizes them, so ePHPm's missing GD JPEG/WebP
  support (`issues/koel.md`) should not matter here — not exercised by
  `test.sh`.
