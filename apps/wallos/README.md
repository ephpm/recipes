# Wallos on ePHPm

| | |
|---|---|
| App | [Wallos](https://github.com/ellite/Wallos) v5.8.3 (`WALLOS_VERSION` build arg) — plain PHP, SQLite |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `bellamy/wallos` image (nginx + php-fpm + dcron) |
| Default stack | `compose.yml` — ePHPm + cron sidecar; no database server (Wallos keeps its own SQLite file) |
| Single container | the default stack already is one application container; the cron sidecar only runs Wallos's scheduled scripts |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, database creation + migrations on start, register the first user through the form, log in through the login form, add a subscription through the app's endpoint and read it back on the subscriptions page, run `updatenextpayment.php` inside the cron service |

## What changes versus the official image

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime; there is no nginx and no php-fpm. The `try_files` chain and the
  deny rules of Wallos's `nginx.default.conf` are reproduced in
  `ephpm.toml` (`[server] fallback`, `[server.security] blocked_paths`).
* **Same database, same layout.** Wallos opens `db/wallos.db` with PHP's
  `sqlite3` extension; the `wallos-db` volume holds it (as `./db` does in
  the official compose file) and `wallos-logos` holds uploaded logos and
  avatars. The entrypoint runs the same first-start scripts as the official
  `startup.sh` (`createdatabase.php`, `migrate.php`, then the payment-date
  / exchange-rate / update checks in the background).
* **Cron jobs run in a sidecar.** Wallos's own `cronjobs` file is installed
  as the crontab at build time (with `php` replaced by `ephpm php` and the
  output sent to the container log) and a second container from the same
  image runs `cron -f`. The official image runs dcron inside the app
  container.
* **No PUID/PGID.** Everything runs as root inside the container, as the
  `ephpm/ephpm` image does.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Register the first user on the first visit (it becomes the admin). `TZ`
sets the container time zone (the official image's only variable).

```bash
docker compose exec cron sh -c 'cd /var/www/html && ephpm php endpoints/cronjobs/updateexchange.php'   # run a job by hand
docker compose exec cron crontab -l                                                                     # the installed schedule
docker compose logs ephpm                                                                               # PHP errors and ePHPm's log
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Fetches the Wallos release, installs `cron`, converts Wallos's crontab, copies the app onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (routing + the nginx deny rules) |
| `entrypoint.sh` | Seeds the volumes, creates/migrates the SQLite database, starts `ephpm serve` (or runs the given command) |
| `compose.yml` | The stack: ePHPm + cron |
| `test.sh` | The smoke test CI runs (`bash apps/wallos/test.sh`) |

## Configuration notes

* Uploads/restores: `[server.request] max_body_size` and the
  `upload_max_filesize` / `post_max_size` ini overrides are 256 MiB, the
  official nginx `client_max_body_size`.
* `[server.security] blocked_paths` denies `/db/*`, `/includes/*`,
  `/.tmp/*` and PHP files under the logo upload directory, mirroring the
  official nginx config; the three multi-tenant flags are set to `false`
  explicitly because they only act in ePHPm's multi-tenant mode.
* Wallos's endpoints resolve `../../includes/...` and `../../db/wallos.db`
  relative to the executing script's directory, which ePHPm (like php-fpm)
  makes the working directory of each request. The cron entries `cd` to
  `/var/www/html` first for the same reason.
* A "database is locked" warning can appear in the log during the first
  minute: the background first-start scripts and the first registration
  share the SQLite file (Wallos sets a 5 s busy timeout, so both complete).
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After changing PHP files inside a running container run
  `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* **ePHPm's GD build has no JPEG/WebP/AVIF support** (PNG/GIF/BMP only —
  `issues/koel.md`). Wallos resizes uploaded and fetched logos with GD, so
  JPEG/WebP logos fail; PNG and GIF work. `test.sh` uploads no logo.
* Email notifications, exchange rates and update checks need outbound
  internet from the containers.
