# Pterodactyl Panel on ePHPm

| | |
|---|---|
| App | [Pterodactyl Panel](https://pterodactyl.io) v1.15.1 (`PTERODACTYL_VERSION` build arg) — Laravel 12 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm + supervisord (queue worker) + crond (scheduler) — the `ghcr.io/pterodactyl/panel` image |
| Default stack | `compose.yml` — ePHPm + queue worker + scheduler (same image) + MariaDB 11 + Redis |
| Single container | none — the panel's queue needs a broker the worker sidecar can reach (Redis, as upstream), and its MySQL schema dump is loaded with the `mysql` CLI |
| Status | tested 2026-10-11 on v0.11.3-php8.5: migrate + seed + admin user on first start, JSON login through `/auth/login` (XSRF cookie), client API account, create a location through the admin form and read it back, the queue worker processes the welcome-mail job, scheduler runs, `p:location:make` on the embedded PHP |

The panel only. **Wings**, the daemon that runs game servers on each node,
is a Go binary and is installed on the nodes as usual; point it at this
panel's `APP_URL`.

## What changes versus the official image

* **One web process.** ePHPm serves `public/` with the nginx
  `try_files $uri $uri/ /index.php?$query_string` rule as `[server]
  fallback`. The queue worker (`queue:work --queue=high,standard,low`, the
  official supervisord program) and the scheduler (`schedule:run` every
  minute, the official crontab) are the `queue` and `scheduler` services,
  running the same image with `ephpm php artisan ...`.
* **Same layout and variables.** `.env` with `APP_KEY` and `HASHIDS_SALT`
  is generated once into the `/app/var` volume, as the official entrypoint
  does; everything else (`APP_URL`, `DB_*`, `REDIS_HOST`, `CACHE_DRIVER`,
  `SESSION_DRIVER`, `QUEUE_CONNECTION`, `MAIL_*`, `APP_SERVICE_AUTHOR`,
  `TRUSTED_PROXIES`, ...) comes from the container environment.
  `migrate --seed --force` runs at every start of the `ephpm` service, as
  upstream.
* **First admin from the environment.** On the first start the entrypoint
  runs `p:user:make --admin=1` with `PTERODACTYL_ADMIN_EMAIL` /
  `_USERNAME` / `_PASSWORD` (upstream leaves this to you).
* **reCAPTCHA off by default** (`RECAPTCHA_ENABLED=false`). Upstream ships it
  enabled with Google's shared keys; for a public panel set your own keys
  (`RECAPTCHA_WEBSITE_KEY`, `RECAPTCHA_SECRET_KEY`) and turn it on.
* **No certbot.** Terminate TLS in front (or use ePHPm's own `[server.tls]`
  ACME support) instead of the image's certbot/nginx SSL config;
  `LE_EMAIL` is not used.
* **`PHP_BINARY=/usr/local/bin/php` in the image.** Laravel starts every
  scheduled command as `<PHP_BINARY> artisan ...`; under `ephpm php` the
  `PHP_BINARY` constant is `ephpm`, so without this the scheduler would run
  `ephpm artisan ...`, fail, and still print `DONE`
  ([`issues/pterodactyl.md`](../../issues/pterodactyl.md)). Symfony's
  `PhpExecutableFinder` prefers the environment variable, which points at
  the `php` → `ephpm php` shim.
* `mariadb-client` is installed: the panel ships a schema dump that
  `migrate` loads through the `mysql` CLI on a fresh database (the official
  image installs `mysql-client` for the same reason).
* Redis stays a real Redis: it is the queue broker the worker sidecar reads
  (and the panel's cache and sessions, shared with the sidecars). ePHPm's
  own KV listener sits on `127.0.0.1:6380` inside the container, off the
  Redis port, so a `REDIS_HOST=127.0.0.1` mistake fails loudly instead of
  putting the queue in an in-process store the worker sidecar cannot see.

## Run

```bash
docker compose up -d                    # or: podman compose up -d
open http://localhost:8080              # EPHPM_PORT=8090 APP_URL=http://localhost:8090 ... to change
```

Log in with `PTERODACTYL_ADMIN_EMAIL` / `PTERODACTYL_ADMIN_PASSWORD`
(`admin@example.com` / `Ptero-Admin-Pass-1` by default — change them, and
`DB_PASSWORD` / `DB_ROOT_PASSWORD`, in a `.env` file). `APP_URL` must be the
address browsers and Wings use.

```bash
docker compose exec ephpm ephpm php artisan p:user:make
docker compose exec ephpm ephpm php artisan p:location:make --short=eu1 --long="Europe 1"
docker compose exec ephpm ephpm php artisan p:environment:mail     # interactive
docker compose restart ephpm                                        # after changing PHP files (reloads OPcache)
```

`php` on PATH inside the image is a shim for `ephpm php`, so
`docker compose exec ephpm php artisan ...` works too.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Release tarball (built front-end) + `composer install`, `mariadb-client`, onto `ephpm/ephpm` |
| `ephpm.toml` | Server config: front controller, 100 MiB uploads, 300 s timeout (the official nginx values) |
| `entrypoint.sh` | `.env` with APP_KEY/HASHIDS_SALT, waits for the DB, `migrate --seed`, first admin, `ephpm serve`; sidecars wait for the server's setup |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/pterodactyl/test.sh`) |

## Configuration notes

* Behind a TLS-terminating proxy set `TRUSTED_PROXIES` (the panel's own
  setting) **and** `[server.security] trusted_proxies` in `ephpm.toml`, and
  use the `https://` URL in `APP_URL`.
* Mail goes to the log by default (`MAIL_MAILER=log`); set `MAIL_MAILER=smtp`
  and the `MAIL_*` variables for real mail.
* OPcache runs with timestamp validation off (`ephpm serve` default); after
  changing PHP files in the container, `docker compose restart ephpm`
  (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* On PHP 8.5 every artisan command prints `PDO::MYSQL_ATTR_*` deprecation
  notices (from the panel's `config/database.php`) to the console. Harmless;
  they are not shown in web responses.
* No single-container variant (see the table).
