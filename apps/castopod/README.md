# Castopod on ePHPm

| | |
|---|---|
| App | [Castopod](https://castopod.org) 1.15.5 (`CASTOPOD_VERSION` / `CASTOPOD_BUNDLE` build args) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.4` (the official image ships PHP 8.4) |
| Replaces | the official `castopod/castopod` image (FrankenPHP + supercronic under s6-overlay) |
| Default stack | `compose.yml` — ePHPm + the scheduled-tasks runner + MariaDB 11 |
| Single container | not available — Castopod is MySQL/MariaDB only and its CodeIgniter migrations use MySQL-only DDL that the embedded database rejects (same class of gap as [issues/invoiceplane.md](../../issues/invoiceplane.md)) |
| Status | tested 2026-10-11 on v0.11.3-php8.4: `.env` + migrations by the entrypoint, super-admin created through the install wizard, login through the auth form, admin dashboard and new-podcast page served, public home page, `spark list` on the console |

## What changes versus the official image

* **Two services instead of s6-overlay.** The official image supervises
  FrankenPHP and a supercronic cron (`spark tasks:run` every minute).
  Here `ephpm` serves the app and a `cron` service runs the same image in a
  `spark tasks:run` loop.
* **Same environment variables as `castopod/castopod`:** `CP_BASEURL`,
  `CP_MEDIA_BASEURL`, `CP_ADMIN_GATEWAY`, `CP_AUTH_GATEWAY`,
  `CP_ANALYTICS_SALT`, `CP_DATABASE_*` (or the `MYSQL_*` fallbacks),
  `CP_DISABLE_HTTPS`, `CP_ENABLE_2FA`, `CP_EMAIL_SMTP_*`. `entrypoint.sh`
  writes `/app/.env` from them on every start, as the official
  `prepare-environment.sh` does, then runs `spark castopod:database-update`
  and `spark cache:clear`.
* **Two differences:** `CP_ANALYTICS_SALT` is generated once into the
  `writable` volume when unset (the official image requires it), and the
  Redis cache handler (`CP_REDIS_*`) and S3 media storage are not wired —
  the file cache handler and local media are used.
* **Release bundle, no build.** The image downloads the "Castopod Package"
  tarball from `code.castopod.org` (vendor and compiled assets included);
  nothing runs Composer or pnpm. The package URL carries a per-release
  upload hash, so it is pinned as `CASTOPOD_BUNDLE`.
* **`spark` runs on the embedded PHP:**
  `docker compose exec ephpm spark castopod:database-update`.

## Run

```bash
CP_BASEURL=http://localhost:8080 docker compose up -d
open http://localhost:8080/cp-install     # creates the super-admin, then log in at /cp-auth/login
```

`CP_BASEURL` must be the URL listeners use (the podcast feeds embed it);
remove `CP_DISABLE_HTTPS` behind TLS — Castopod requires https to federate.

```bash
docker compose exec ephpm spark tasks:run      # what the cron service does every minute
docker compose logs -f cron
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release bundle onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, upload limits, timeouts) |
| `entrypoint.sh` | Seeds the volumes, writes `.env`, waits for the DB, migrates, starts `ephpm serve` (or the cron loop) |
| `spark` | CodeIgniter console wrapper over the embedded PHP |
| `compose.yml` | ePHPm + cron + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/castopod/test.sh`) |

## Configuration notes

* `public/media` (audio, images) and `writable/` (cache, sessions, logs,
  uploads, the generated salt) are volumes.
* Uploads: `[server.request] max_body_size` is 512 MiB and the ini
  overrides match the official `PHP_UPLOAD_MAX_FILE_SIZE` /
  `PHP_POST_MAX_SIZE` / `PHP_MEMORY_LIMIT` / `PHP_MAX_EXECUTION_TIME`
  defaults; `[server.timeouts] request = 600` for long uploads.
* Sessions use CodeIgniter's file handler in `writable/session`.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and an `https://` `CP_BASEURL`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default); the
  entrypoint clears Castopod's own cache on every start.

## Known limitations

* **No `ffmpeg`.** The official image installs it for video clips and
  audio processing (transcript/chapter extraction keeps working without
  it). Add `RUN apt-get update && apt-get install -y ffmpeg` to a derived
  image if you need clips.
* The GeoLite2 City database (listener geolocation) is not bundled; the
  official build downloads it with a MaxMind licence key at image build
  time. Drop `GeoLite2-City/` into the `writable/uploads` volume to enable it.
* `imagick` is not available; image handling uses GD (compiled in).
