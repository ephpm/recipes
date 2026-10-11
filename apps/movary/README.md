# Movary on ePHPm

| | |
|---|---|
| App | [Movary](https://movary.org) 0.77.0 (`MOVARY_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` (Movary needs PHP 8.5) |
| Replaces | the official `leepeuker/movary` image (nginx + php-fpm + the job worker under supervisord) |
| Default stack | `compose.yml` — ePHPm + the job worker + MariaDB 11 |
| Single container | `compose.sqlite.yml` — Movary's own SQLite file (its default) + the job worker. ePHPm's embedded database is not shipped: Movary's migrations use `ALTER TABLE … ADD CONSTRAINT`, which it rejects ([issues/easyappointments.md](../../issues/easyappointments.md)) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml` and `compose.sqlite.yml`): migrations + admin by the entrypoint, login through the token endpoint the login page uses, dashboard and account settings served, `user:list` on the console |

## What changes versus the official image

* **Two services instead of supervisord.** The official image runs nginx,
  php-fpm and the `jobs:process` worker under supervisord in one container.
  Here `ephpm` serves the app and a second `jobs` service runs the same
  image in a `jobs:process` loop (the worker exits after each pass by
  design; supervisord restarted it, the loop does the same).
* **Same environment variables as `leepeuker/movary`**
  ([docs/configuration.md](https://github.com/leepeuker/movary/blob/0.77.0/docs/configuration.md)):
  `TMDB_API_KEY`, `APPLICATION_URL`, `APPLICATION_SECRET`, `DATABASE_MODE`,
  `DATABASE_MYSQL_*`, `DATABASE_SQLITE`, `TIMEZONE`, `ENABLE_REGISTRATION`,
  `LOG_*`, `SMTP_*`, `PLEX_*`, `JELLYFIN_*`,
  `DATABASE_DISABLE_AUTO_MIGRATION`. Movary reads them itself.
* **Two additions:** `APPLICATION_SECRET` is generated once into the
  `storage` volume when unset (the official image requires it), and
  `ADMIN_EMAIL` / `ADMIN_PASSWORD` / `ADMIN_NAME` create the first admin
  on start (otherwise the first visit shows Movary's create-user page).
* **Built from the release tag.** No dist archive exists; the build stage
  runs Composer (the frontend is plain JS/CSS under `public/`, nothing to
  compile). `imagick`, which the official image adds, is not available;
  Movary only uses it for optional image handling.
* **The console runs on the embedded PHP:**
  `docker compose exec ephpm movary user:create ...` (`movary` wraps
  `ephpm php bin/console.php` and loads the generated secret).

## Run

```bash
TMDB_API_KEY=... ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=change-me docker compose up -d
open http://localhost:8080
```

`TMDB_API_KEY` is required for movie data (a free account at
themoviedb.org); the app starts without it but cannot look anything up.
`APPLICATION_URL` must be the URL users open.

```bash
docker compose exec ephpm movary user:list
docker compose exec ephpm movary tmdb:movie:sync
docker compose logs -f jobs
```

### Single container, Movary's SQLite (supported)

```bash
TMDB_API_KEY=... ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=change-me docker compose -f compose.sqlite.yml up -d
```

Movary's default: `storage/movary.sqlite` in the `storage` volume (plus the
`jobs` service).

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Composer build stage from the release tag, copied onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds `storage/`, resolves the secret, waits for the DB, migrates, `storage:link`, creates the admin, starts `ephpm serve` (or runs the `jobs` command) |
| `movary` | `bin/console.php` wrapper over the embedded PHP |
| `compose.yml`, `compose.sqlite.yml` | The two stacks |
| `test.sh` | The smoke test CI runs (`bash apps/movary/test.sh`) |

## Configuration notes

* `storage/` (SQLite file, logs, cached images, the generated secret) is a
  volume shared by the `ephpm` and `jobs` services.
* Uploads/imports: `[server.request] max_body_size` is 100 MiB with
  matching ini overrides; `[server.timeouts] request = 300` for imports
  that run inside the request.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and an `https://` `APPLICATION_URL` (Movary then marks its cookies
  `Secure`).
* OPcache runs with timestamp validation off (ePHPm's `serve` default). After
  changing PHP files run `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* `imagick` is not available (the official image installs it); GD is.
