# CodeIgniter 4 on ePHPm

| | |
|---|---|
| App | [CodeIgniter 4](https://codeigniter.com) 4.7 `appstarter` skeleton (`CI4_VERSION` build arg) + a 2-file guestbook demo |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | apache/nginx + php-fpm, `php spark serve`, FrankenPHP (worker mode — see below) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | `compose.embedded.yml` — ePHPm with its embedded database (**experimental**) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (both variants): welcome page, `spark migrate` on start, a guestbook entry POSTed over HTTP and read back as JSON (MySQLi through the real and the embedded database) |

The skeleton has no database-backed page, so the recipe adds
`demo/CreateGuestbook.php` (migration) and `demo/Guestbook.php` (controller)
plus two routes, purely so `test.sh` can prove a round trip. For your own
application replace the `composer create-project` line in the `Dockerfile`
with `COPY . /app` + `composer install` and drop the `demo/` lines.

## What changes versus apache/nginx + php-fpm

* **One process.** `[server] fallback` in `ephpm.toml` replaces
  `public/.htaccess`'s rewrite to `index.php`; `document_root` is `public/`.
* **Configuration from the environment.** CI4 reads `CI_ENVIRONMENT`,
  `app_baseURL`, `database_default_*` (the underscore form of the `.env`
  keys) from real environment variables, which ePHPm passes through to PHP.
  No `.env` file is baked into the image.
* **`spark` on the embedded PHP:** `docker compose exec ephpm ephpm php spark ...`.
  `entrypoint.sh` runs `spark migrate --all` on every start (`SKIP_MIGRATE=1`
  to disable).
* **Cache/sessions without Redis.** The loopback RESP listener in
  `ephpm.toml` lets CI4's `redis` cache and session handlers point at
  `127.0.0.1:6379` with `predis/predis` installed (or the `redis` extension
  from ePHPm's extension catalog).

## Run

```bash
docker compose up -d                          # MariaDB
docker compose -f compose.embedded.yml up -d  # single container (experimental)
curl -d name=me -d message=hi http://localhost:8080/guestbook
curl http://localhost:8080/guestbook
```

## Worker mode

CodeIgniter 4.7 ships an experimental worker mode whose only supported
server is FrankenPHP (`php spark worker:install` writes a `Caddyfile` and
`public/frankenphp-worker.php` built on `frankenphp_handle_request()`).
ePHPm's worker mode uses a different request loop (the `ephpm/worker`
envelope API), so that file does not run on ePHPm and **this recipe uses
per-request mode**. A CI4 adapter for ePHPm's worker mode does not exist
yet; see `UPSTREAM.md` for the proposed addition to CI4's docs.

## Configuration notes

* `[server.security] blocked_paths` keeps `/app`, `/writable`, `/vendor` and
  `.env` off the web even though only `public/` is the document root.
* After deploying new code run `docker compose exec ephpm ephpm cache reset`
  or restart (OPcache timestamp validation is off under `ephpm serve`).

## Known limitations

* The embedded-database variant is experimental (Turso is Beta upstream).
  The demo migration is a plain `CREATE TABLE`; migrations that use
  `ALTER TABLE … ADD CONSTRAINT`/`MODIFY` fail there (see `ISSUES.md`).
* GD in ePHPm has no JPEG/WebP support; CI4's image manipulation class
  works for PNG/GIF only.
