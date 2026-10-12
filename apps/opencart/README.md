# OpenCart on ePHPm

| | |
|---|---|
| App | [OpenCart](https://www.opencart.com) 4.1.0.4 (`OPENCART_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | a nginx + php-fpm (or apache) host — OpenCart has no official production image |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not offered — not attempted on ePHPm's embedded database |
| Status | **blocked** — ePHPm's GD has no JPEG support: the CLI installer completes and the admin login page answers, but the storefront home page renders `Error: Call to undefined function …imagecreatefromjpeg()` (the "Featured" module resizes the bundled demo catalogue's JPEG product images through `system/library/image.php`), 2026-10-11 on v0.11.3-php8.5 |

**This recipe does not produce a usable shop on ePHPm v0.11.3.** Any page
that shows a product, category or banner image resizes it with GD on first
view, and the images OpenCart installs (and that merchants upload) are
JPEG. The files are kept so it can be re-checked once the php-sdk's GD
build gains JPEG (and WebP) support — the gap recorded in
[issues/koel.md](../../issues/koel.md).

## What the recipe does

* **One process serves the shop.** ePHPm serves `upload/` (the release's
  web root) and runs PHP; OpenCart's `.htaccess.txt` SEO rewrite (anything
  not on disk → `index.php`) is `[server] fallback`, and
  `[server.security] blocked_paths` covers what its `.htaccess` files deny
  (`system/storage`, `*.twig`, `*.ini`, logs, PHP under `image/`).
* **Unattended install.** On the first start the entrypoint copies the
  shop into the `html` volume, creates `config.php` / `admin/config.php`
  from the `-dist` files, runs `install/cli_install.php install` with the
  `DB_*`, `OPENCART_URL`, `OPENCART_ADMIN_EMAIL` and
  `OPENCART_ADMIN_PASSWORD` variables, and removes `install/`. Without the
  admin variables it leaves `/install/` for the web installer.
* **The docroot is `/var/www/opencart`, not `/var/www/html`**: the
  `ephpm/ephpm` base image ships demo PHP files in `/var/www/html`, which a
  fresh named volume mounted there would be pre-populated with.

## Run (to reproduce)

```bash
OPENCART_ADMIN_EMAIL=you@example.com OPENCART_ADMIN_PASSWORD=change-me docker compose up -d
curl -s http://localhost:8080/ | head -3     # Error: Call to undefined function ...imagecreatefromjpeg()
docker compose down -v
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Unpacks the release zip's `upload/` onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, blocked paths, limits) |
| `entrypoint.sh` | Copies the shop into the volume, waits for the DB, runs the CLI installer once, starts `ephpm serve` |
| `compose.yml` | ePHPm + MariaDB |
| `test.sh` | The smoke test (fails on the storefront check today) |

## Known limitations

* **Blocked:** GD without JPEG (see Status).
* OpenCart shows PHP errors to visitors by default (`config_error_display`
  in the settings); turn that off in a real shop.
* Not exercised beyond install, the admin login page and the storefront
  error: checkout, extensions, the cron endpoint.
