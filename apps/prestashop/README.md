# PrestaShop on ePHPm

| | |
|---|---|
| App | [PrestaShop](https://prestashop-project.org) 9.2.0 (`PRESTASHOP_ZIP` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` (PrestaShop 9.2 supports PHP 8.1–8.5) |
| Replaces | the official `prestashop/prestashop` image (php-apache with mod_rewrite) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not offered — PrestaShop is MySQL/MariaDB only |
| Status | **blocked** — ePHPm's GD has no JPEG support: the installer's theme step calls `imagecreatefromjpeg()` (resizing the bundled language flag images) and aborts with `Call to undefined function imagecreatefromjpeg()`, 2026-10-11 on v0.11.3-php8.5. PrestaShop also lists GD-with-JPEG as a hard requirement in its system check |

**This recipe does not produce a working shop on ePHPm v0.11.3.** The
files are kept so it can be re-checked once the php-sdk's GD build gains
JPEG (and ideally WebP) support — the same gap recorded for Koel in
[issues/koel.md](../../issues/koel.md). Everything before the theme step
(database, default data, shop creation, language install, module files)
completes on ePHPm.

## What the recipe does

* **Same layout as the official image.** The release archive (from the
  same `api.prestashop-project.org` distribution API the official image
  builds from) is unpacked into the image; on the first start the
  entrypoint copies it into the `html` volume, runs the CLI installer with
  the official image's variables (`PS_INSTALL_AUTO=1`, `DB_SERVER`,
  `DB_NAME`, `DB_USER`, `DB_PASSWD`, `DB_PREFIX`, `PS_DOMAIN`,
  `PS_LANGUAGE`, `PS_COUNTRY`, `PS_FOLDER_ADMIN`, `ADMIN_MAIL`,
  `ADMIN_PASSWD`, …), removes `install/` and renames the back-office
  folder. A failed install stops the container instead of serving a
  half-installed shop.
* **Three front controllers, one fallback.** The shop's friendly URLs go
  to `/index.php`; the back office (`/<PS_FOLDER_ADMIN>/index.php/sell/…`)
  and the Admin API (`/admin-api/…`) are Symfony front controllers Apache
  reaches through `AcceptPathInfo`. ePHPm has no PATH_INFO and no
  per-prefix fallbacks ([issues/espocrm.md](../../issues/espocrm.md)), so
  `front.php` (installed as `/ephpm-front.php`, the `[server] fallback`
  target) picks the entry point by path prefix and sets `SCRIPT_NAME` /
  `SCRIPT_FILENAME` / `PATH_INFO` the way php-fpm would. Untested past the
  installer, since the install does not complete.
* **The docroot is `/var/www/prestashop`, not `/var/www/html`**: the
  `ephpm/ephpm` base image ships demo PHP files in `/var/www/html`, and a
  fresh named volume mounted there is pre-populated with them (the
  entrypoint would then never copy the shop in).
* `[server.security] blocked_paths` mirrors what PrestaShop's own
  `.htaccess` files deny (`app/`, `var/`, `vendor/`, `src/`, `config/`, …)
  and refuses PHP under `upload/` and `img/`.

## Run (to reproduce the failure)

```bash
ADMIN_MAIL=you@example.com ADMIN_PASSWD=change-me docker compose up -d
docker compose logs -f ephpm       # ... Installing theme hummingbird
                                   # Error: Call to undefined function imagecreatefromjpeg()
docker compose down -v
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Unpacks the release archive onto the `ephpm/ephpm` image |
| `front.php` | Per-prefix front controller (shop / back office / Admin API) |
| `ephpm.toml` | Server config (docroot, fallback, blocked paths, limits) |
| `entrypoint.sh` | Copies the shop into the volume, waits for the DB, runs the CLI installer once, starts `ephpm serve` |
| `compose.yml` | ePHPm + MariaDB |
| `test.sh` | The smoke test (fails at the install today) |

## Known limitations

* **Blocked:** GD without JPEG (see Status). Even past the installer, every
  product, category and logo image PrestaShop resizes is JPEG by default.
* Friendly URLs for product images (`/1-home_default/name.jpg`, rewritten
  to `img/p/…` by PrestaShop's generated `.htaccess`) have no equivalent in
  `[server] fallback`; they would need the same kind of front-controller
  shim, or friendly URLs off (`PS_REWRITE=0`).
