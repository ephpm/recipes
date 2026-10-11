# Monica (v4) on ePHPm

| | |
|---|---|
| App | [Monica](https://www.monicahq.com) v4.1.2 (`MONICA_VERSION` build arg) — Laravel 9, PHP ^8.1 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.3` (Monica 4 is pinned to Laravel 9; the official image runs PHP 8.2) |
| Replaces | the `monica:4-apache` image (Apache + mod_php) and its cron sidecar; a Redis service if you ran one |
| Default stack | `compose.yml` — ePHPm + scheduler sidecar + MariaDB 11 |
| Single container | not offered — Monica's migrations add foreign keys with `ALTER TABLE … ADD CONSTRAINT`, which ePHPm's embedded database rejects (the failure recorded for BookStack in `issues/bookstack.md`; not re-run here) |
| Status | blocked — ePHPm's GD build has no FreeType support, and Monica renders a default avatar for every new contact with `imagettfbbox()` (laravolt/avatar + Intervention/Image), so creating a contact answers 500. Exercised on v0.11.3-php8.3: image build, migrations + Passport keys on start, registering the first account, login; contact creation fails. See `issues/monica.md`. |

## What changes versus the official image

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime; there is no Apache. Laravel's front-controller routing comes from
  `[server] fallback` in `ephpm.toml` (Monica's own `nginx_app.conf`
  rewrites every non-file URL to `index.php` the same way).
* **The release tarball is used as-is.** Monica's GitHub release ships
  `vendor/` and the compiled assets, so the image has no Composer or Node
  stage.
* **Same artisan sequence on start as the official entrypoint:**
  `monica:update --force`, then `passport:keys` + `passport:client
  --personal` when the keys do not exist yet.
* **Same environment variables as the official image:** `APP_URL`,
  `APP_ENV`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`,
  `DB_PASSWORD`, `APP_DISABLE_SIGNUP`, `APP_TRUSTED_PROXIES`, `MAIL_*`,
  `CACHE_DRIVER`, `SESSION_DRIVER`, `REDIS_*`, … — every key of Monica's
  `.env.example` can be set in `environment:` and wins over the `.env`
  file. The official entrypoint's `*_FILE` secret indirection is **not**
  implemented.
* **`APP_KEY` and `HASH_SALT` are generated once** by the entrypoint into
  `storage/.env` (`/app/.env` points at it, in the `monica-storage` volume).
  Set either in `environment:` to pin it.
* **The scheduler is a second container from the same image** running
  `ephpm php artisan schedule:run` every minute (reminders, notifications,
  clean-ups) — the official stack's cron sidecar does the same.
* **Cache and sessions:** Monica defaults to the `database` cache store and
  `file` sessions. To put both in ePHPm's in-process KV store instead of
  running a Redis service, set `CACHE_DRIVER=redis`, `SESSION_DRIVER=redis`,
  `REDIS_CLIENT=predis` and `REDIS_HOST=127.0.0.1` (predis ships with
  Monica; the RESP listener is enabled in `ephpm.toml`). Not exercised by
  `test.sh`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Register the first account on the first visit (Monica always allows the
first registration); set `APP_DISABLE_SIGNUP=true` afterwards to close
signups. `APP_URL` must be the address users open Monica at (default
`http://localhost:8080`): `APP_URL=https://monica.example.com docker compose up -d`.

`APP_ENV` defaults to `local` here, not `production` as in the official
image: Monica's `RouteServiceProvider` forces `https://` on every generated
URL in production, which breaks a plain-HTTP deployment (every redirect
goes to `https://localhost:8080`). Once Monica sits behind TLS, set
`APP_ENV=production` (and `APP_URL` to the `https://` URL).

```bash
docker compose exec ephpm ephpm php artisan monica:update        # any artisan command
docker compose exec ephpm ephpm php artisan schedule:run         # what the scheduler service runs every minute
docker compose exec ephpm ephpm kv keys '*'                      # the live KV store (with the redis drivers above)
docker compose logs ephpm                                         # PHP errors and ePHPm's log
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the Monica release tarball, copies it onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds the storage volume and `.env`, generates the keys, waits for the DB, runs `monica:update`, starts `ephpm serve` (or runs the given command) |
| `compose.yml` | The stack: ePHPm, scheduler, MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/monica/test.sh`) |

## Configuration notes

* Uploads up to 64 MiB (`[server.request] max_body_size` + the ini
  overrides); Monica's own `DEFAULT_MAX_UPLOAD_SIZE` (10 MB) applies on top.
* Behind a TLS-terminating proxy set `APP_TRUSTED_PROXIES` and `APP_URL`
  to the public URL (or `APP_FORCE_URL=true`).
* The `monica-storage` volume holds uploads (`storage/app/public`), logs,
  the Passport keys and `.env`. Back it up with the database.
* A queue worker is optional (`QUEUE_CONNECTION=sync` by default); the
  official stack's `queue.sh` is `artisan queue:work --queue=default,migration`
  — run it as another service with `command: ["ephpm", "php", "artisan",
  "queue:work", ...]` if you switch to a database queue.
* CardDAV/CalDAV: the `.well-known/carddav` and `/caldav` redirects in
  Monica's nginx config are not replicated; use the `/dav/` URL directly.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After changing PHP files inside a running container run
  `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* **No single-container variant** (see the table above).
* Monica 4 declares `ext-redis` in `composer.json`; the ePHPm build has no
  phpredis, so use `REDIS_CLIENT=predis` if you point Monica at Redis or at
  ePHPm's KV store.
* **ePHPm's GD build has no JPEG/WebP/AVIF support** (PNG/GIF/BMP only —
  `issues/koel.md`): JPEG contact photos and avatars cannot be resized.
  `test.sh` uploads no image.
* `memcached`/`apcu` (compiled into the official image) are not in the
  ePHPm build; use the `database`, `file` or `redis` cache stores.
