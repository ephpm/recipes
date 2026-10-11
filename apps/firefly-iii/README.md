# Firefly III on ePHPm

| | |
|---|---|
| App | [Firefly III](https://www.firefly-iii.org) v6.7.9 (`FIREFLY_VERSION` build arg) — Laravel 12, PHP ≥ 8.5 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `fireflyiii/core` image (serversideup nginx + php-fpm + s6); a Redis service for cache/sessions if you ran one |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 + the upstream cron sidecar |
| Single container | not offered — 25 of Firefly's migrations add foreign keys with `ALTER TABLE … ADD CONSTRAINT`, which ePHPm's embedded database rejects (the failure recorded for BookStack in `issues/bookstack.md`; not re-run here) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, database upgrade on start, register the first user, new-user wizard creates an asset account, account page renders it, cron endpoint answers 200, `artisan firefly-iii:report-integrity` on the embedded PHP |

## What changes versus the official image

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime; there is no nginx, no php-fpm and no s6. Laravel's
  front-controller routing comes from `[server] fallback` in `ephpm.toml`
  (Firefly's own `nginx_app.conf` rewrites every non-file URL to
  `index.php` the same way).
* **The release tarball is used as-is.** Firefly's GitHub release ships
  `vendor/` and the built assets (`public/build`) — the official image
  unzips the same archive — so the image has no Composer or Node stage.
* **The same artisan sequence on start as the official entrypoint:**
  `firefly-iii:create-database`, `firefly-iii:upgrade-database`,
  `firefly-iii:laravel-passport-keys`, `firefly-iii:set-latest-version`,
  then `event:clear` / `cache:clear`. A fresh database gets the schema; an
  existing one is upgraded.
* **Same environment variables as the official image.** `APP_URL`,
  `SITE_OWNER`, `TZ`, `TRUSTED_PROXIES`, `DB_CONNECTION`, `DB_HOST`,
  `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`,
  `STATIC_CRON_TOKEN`, `CACHE_STORE`, `SESSION_DRIVER`, `REDIS_*`,
  `MAIL_*`, … — every key of Firefly's `.env.example` can be set in
  `environment:` and wins over the `.env` file. The `*_FILE` secret
  indirection of the official entrypoint is **not** implemented.
* **`APP_KEY` is generated once** by the entrypoint (a plain 32-character
  key, as Firefly's `.env.example` asks for) into `storage/.env`
  (`/app/.env` points at it, in the `firefly-storage` volume). Set `APP_KEY`
  in `environment:` to pin one.
* **The cron sidecar is upstream's.** `compose.yml` runs the same
  `alpine` + `crond` container as Firefly's official `docker-compose.yml`,
  calling `/api/v1/cron/<STATIC_CRON_TOKEN>` daily at 03:00.
* **Cache and sessions** use Laravel's `file` driver by default (as
  upstream). To put them in ePHPm's in-process KV store instead of running a
  Redis service, set `CACHE_STORE=redis`, `SESSION_DRIVER=redis` and
  `REDIS_HOST=127.0.0.1` (predis ships with Firefly; the RESP listener is
  enabled in `ephpm.toml`). Not exercised by `test.sh`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Register the first user on the first visit (it becomes the owner; the
registration page closes afterwards). Change `STATIC_CRON_TOKEN` (exactly 32
characters) and `DB_PASSWORD` in `compose.yml` before exposing the stack.
`APP_URL` must be the address users open Firefly at (default
`http://localhost:8080`; behind a proxy the public `https://` URL):
`APP_URL=https://money.example.com docker compose up -d`.

```bash
docker compose exec ephpm ephpm php artisan firefly-iii:report-integrity   # any artisan command
docker compose exec ephpm ephpm php artisan firefly-iii:cron               # run the cron jobs by hand
docker compose exec ephpm ephpm kv keys '*'                                # the live KV store (with the redis drivers above)
docker compose logs ephpm                                                   # PHP errors and ePHPm's log
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the Firefly III release tarball, copies it onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds the storage volume and `.env`, generates `APP_KEY`, waits for the DB, runs the upgrade commands, starts `ephpm serve` (or runs the given command) |
| `compose.yml` | The stack: ePHPm, MariaDB, cron sidecar |
| `test.sh` | The smoke test CI runs (`bash apps/firefly-iii/test.sh`) |

## Configuration notes

* `max_execution_time` is 300 s (the official image's
  `PHP_MAX_EXECUTION_TIME`) for reports and imports; uploads up to 64 MiB
  (`[server.request] max_body_size` + the ini overrides).
* `TRUSTED_PROXIES=**` (the official Docker default) makes Firefly honour
  `X-Forwarded-*` from whatever is directly in front of it; behind a
  TLS-terminating proxy also set `APP_URL` to the `https://` URL.
* The `firefly-storage` volume holds uploads (`storage/upload`), logs, the
  Passport keys (`storage/oauth-*.key`) and `.env`. Back it up with the
  database.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After changing PHP files inside a running container run
  `docker compose exec ephpm ephpm cache reset` or restart it.
* The Firefly III Data Importer is a separate application (own image); run
  it as another service pointed at this one's URL, as upstream documents.

## Known limitations

* **No single-container variant** (see the table above).
* The official entrypoint's `VARIABLE_FILE` secret files are not supported
  by this entrypoint; pass secrets as plain variables or compose secrets
  rendered into `environment:`.
* `memcached` (compiled into the official image) is not in the ePHPm build;
  use the `file` or `redis` cache store.
