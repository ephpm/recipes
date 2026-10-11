# CakePHP 5 on ePHPm

| | |
|---|---|
| App | [CakePHP](https://cakephp.org) 5.4 `cakephp/app` skeleton (`CAKE_VERSION` build arg) + a 3-file guestbook demo |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | apache/nginx + php-fpm, `bin/cake server` |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not offered — CakePHP's schema dialect uses `SHOW FULL TABLES FROM … WHERE TABLE_TYPE IN (…)`, which ePHPm's embedded database rejects (see `issues/cakephp.md`) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): Phinx migration on start, a guestbook entry created over HTTP through the skeleton's CSRF middleware (token from the JSON index, `X-CSRF-Token` header; a POST without it is refused with 403) and read back through the ORM |

The skeleton has no database-backed page, so the recipe adds a migration
(`demo/CreateGuestbook.php`), a Table class and a JSON controller purely so
`test.sh` can prove a round trip. For your own application replace the
`composer create-project` line in the `Dockerfile` with `COPY . /app` +
`composer install` and drop the `demo/` lines.

## What changes versus apache/nginx + php-fpm

* **One process.** `[server] fallback = ["$uri", "/index.php?$query_string"]`
  is `webroot/.htaccess`'s `RewriteRule ^ index.php`; `document_root` is
  `webroot/`.
* **Configuration from the environment.** `config/app_local.php` (copied from
  the example at build time) reads `DEBUG`, `SECURITY_SALT`, `DATABASE_URL`
  and `EMAIL_TRANSPORT_DEFAULT_URL` with `env()`, which sees the container
  environment. `SECURITY_SALT` is generated once into the `tmp` volume when
  not provided.
* **`bin/cake` on the embedded PHP:** `docker compose exec ephpm ephpm php bin/cake.php ...`
  (`bin/cake.php` directly — the `bin/cake` shell wrapper looks for a `php`
  binary on `PATH`, which the image does not have). `entrypoint.sh` runs
  `migrations migrate` on every start (`SKIP_MIGRATE=1` to disable).
* **Cache without Redis.** The loopback RESP listener in `ephpm.toml` lets
  CakePHP's `RedisEngine` target `127.0.0.1:6379` (with the `redis`
  extension from ePHPm's extension catalog, or predis via a custom engine).

## Run

```bash
docker compose up -d
curl -c jar http://localhost:8080/guestbook          # note "csrfToken"
curl -b jar -H "X-CSRF-Token: <token>" -d name=me -d message=hi http://localhost:8080/guestbook/add
```

## Configuration notes

* The skeleton's `templates/Pages/home.php` deliberately throws
  `NotFoundException` when `DEBUG` is false, so `/` is a 404 in production
  until you replace it; `DEBUG=true` shows the stock landing page.
* `blocked_paths` keeps `/config`, `/src`, `/tmp`, `/logs` and `/vendor`
  off the web even though only `webroot/` is served.
* After deploying new code run `docker compose exec ephpm ephpm cache reset`
  or restart (OPcache timestamp validation is off under `ephpm serve`).

## Known limitations

* No embedded-database variant (see the table above).
* GD in ePHPm has no JPEG/WebP support (`ISSUES.md`).
