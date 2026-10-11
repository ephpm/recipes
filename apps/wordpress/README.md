# WordPress on ePHPm

| | |
|---|---|
| App | [WordPress](https://wordpress.org) 7.1.3 (`WP_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx/apache + php-fpm (the `wordpress:*` images), Redis + the Redis Object Cache plugin |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | `compose.embedded.yml` — ePHPm with its embedded database (**experimental**) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (both variants): installer, login, publish a post with WP-CLI, object-cache keys visible in the KV store |

## What changes versus the official image

* **One process.** ePHPm is the HTTP server and the PHP runtime. There is no
  php-fpm socket, no `.htaccess` and no nginx `try_files`; pretty permalinks
  come from `[server] fallback` in `ephpm.toml`.
* **Object cache without Redis.** `wp-content/object-cache.php` is the
  [`ephpm/cache-wordpress`](https://github.com/ephpm/cache-wordpress) drop-in,
  which stores WordPress's object cache in ePHPm's in-process KV store through
  the `ephpm_kv_*` functions. `wp_cache_flush()` really flushes. Nothing to
  activate; remove `wp-content/object-cache.php` to turn it off.
* **WP-CLI runs on the embedded PHP.** `docker compose exec ephpm wp ...`
  (`wp` wraps `ephpm php wp-cli.phar`), so CLI and web share one PHP build.
* **Same environment variables as the official image.** `WORDPRESS_DB_HOST`,
  `WORDPRESS_DB_USER`, `WORDPRESS_DB_PASSWORD`, `WORDPRESS_DB_NAME`,
  `WORDPRESS_TABLE_PREFIX`, `WORDPRESS_DEBUG`, `WORDPRESS_CONFIG_EXTRA` and the
  `WORDPRESS_AUTH_KEY`… salts are read by the bundled `wp-config.php`. Salts
  not given are generated once and kept in the `wp-content` volume
  (`wp-content/ephpm-salts.php`).

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

The web installer appears on first visit. Afterwards:

```bash
docker compose exec ephpm wp plugin install woocommerce --activate
docker compose exec ephpm wp cache flush
docker compose exec ephpm ephpm kv keys 'wp:*'      # the live object cache
```

### Single container, embedded database (experimental)

```bash
docker compose -f compose.embedded.yml up -d
```

No MariaDB. ePHPm opens an embedded SQLite-compatible database (the Turso
engine, Beta upstream) and serves it on the MySQL wire protocol at
`127.0.0.1:3306` inside the container, where WordPress's stock `mysqli` driver
connects — no SQLite plugin, no `db.php` drop-in. The data lives in the
`ephpm-data` volume (`/var/lib/ephpm/wordpress.db`). Good for development,
previews and small sites; plugins that rely on MySQL-only SQL may misbehave.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads WordPress + WP-CLI + the object-cache drop-in, copies them onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config for the MariaDB stack |
| `ephpm.embedded.toml` | Server config with `[db.sqlite]` for the single-container variant |
| `wp-config.php` | Environment-driven config (official-image variable names) |
| `entrypoint.sh` | Seeds the `wp-content` volume, generates salts, waits for the DB, starts `ephpm serve` |
| `wp` | WP-CLI wrapper over the embedded PHP |
| `compose.yml`, `compose.embedded.yml` | The two stacks |
| `test.sh` | The smoke test CI runs (`bash apps/wordpress/test.sh`) |

## Configuration notes

* Uploads: `[server.request] max_body_size` (64 MiB) and the
  `upload_max_filesize` / `post_max_size` ini overrides move together.
* `[server.security] blocked_paths` refuses PHP under `wp-content/uploads/`
  and `xmlrpc.php`. The three `open_basedir` / `disable_shell_exec` /
  `multi_tenant_hardening` flags are set to `false` explicitly because they
  only act in ePHPm's multi-tenant mode; left unset they would just log
  warnings here.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies` and
  the bundled `wp-config.php` honours `X-Forwarded-Proto`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default). After
  updating plugins or core from the admin UI run
  `docker compose restart ephpm` so the new code is picked up (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).
* Cron: WordPress's pseudo-cron runs on page views as usual. For a real
  schedule add a host cron entry running
  `docker compose exec -T ephpm wp cron event run --due-now`.

## Known limitations

* **Image thumbnails for JPEG/WebP are not generated.** `imagick` is not
  available in the ePHPm build, and its bundled GD has no JPEG, WebP or AVIF
  support (`gd_info()` on v0.11.3: PNG/GIF/BMP only, no FreeType). Uploads
  succeed, but WordPress cannot create the resized sizes for JPEG/WebP files
  and serves the original. Tracked in the repo's `ISSUES.md`.
* The embedded-database variant is experimental: the Turso engine is Beta
  upstream, and WordPress plugins that use MySQL-specific SQL may fail.
* `WP_DEBUG_LOG` goes to the container's stderr (`docker compose logs ephpm`).
