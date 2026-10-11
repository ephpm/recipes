# YOURLS on ePHPm

| | |
|---|---|
| App | [YOURLS](https://yourls.org) 1.10.6 (`YOURLS_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the `yourls:apache` image) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | none — YOURLS's schema uses column-level `CHARACTER SET`/`COLLATE`, which ePHPm's embedded database rejects (see `issues/yourls.md`) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: installer, admin login, shorten a URL through the API with the signature token, follow the short link, click count via the API, private paths 403 |

## What changes versus the official image

* **One process.** ePHPm serves the files and runs PHP. The `.htaccess`
  YOURLS writes at install time (`RewriteRule ^.*$ /yourls-loader.php`) is
  `[server] fallback` in `ephpm.toml`; the code-only `includes/` directory
  and `user/config.php` are refused with `[server.security] blocked_paths`.
* **Same environment variables as the official image.** `YOURLS_SITE`,
  `YOURLS_USER`, `YOURLS_PASS`, `YOURLS_DB_HOST`, `YOURLS_DB_USER`,
  `YOURLS_DB_PASS`, `YOURLS_DB_NAME`, `YOURLS_DB_PREFIX`, `YOURLS_COOKIEKEY`,
  `YOURLS_PRIVATE`, `YOURLS_UNIQUE_URLS`, `YOURLS_HOURS_OFFSET`,
  `YOURLS_LANG`, `YOURLS_URL_CONVERT`, `YOURLS_DEBUG`,
  `YOURLS_NO_VERSION_CHECK`, `YOURLS_NOSTATS`, and the `*_FILE` secret
  variants — the bundled `user/config.php` reads them the way the official
  `config-container.php` does. A cookie key not given is generated once into
  the `user` volume (`user/cookiekey.txt`).
* **`user/` is the volume** (plugins, pages, languages, `config.php`),
  seeded from the image on first start; the application code stays in the
  image and is replaced by rebuilding. The official image instead copies
  the whole tree into a `/var/www/html` volume.

## Run

```bash
docker compose up -d                # or: podman compose up -d
open http://localhost:8080/admin/   # EPHPM_PORT=8090 ... to change — then set
                                    # YOURLS_SITE=http://localhost:8090 as well
```

The first visit to `/admin/install.php` creates the tables (one click);
then log in with `YOURLS_USER` / `YOURLS_PASS` (`admin` /
`yourls-admin-password` by default — change them in `compose.yml` or a
`.env` file). `YOURLS_SITE` **must** be the public URL of the instance:
short links are built from it and the login cookie is scoped to its host.

```bash
# the API (signature token from Admin → Tools)
curl "http://localhost:8080/yourls-api.php" \
  --data "signature=TOKEN&action=shorturl&url=https://example.com/&format=json"
docker compose exec ephpm ephpm cache reset   # after changing PHP files in user/
```

### No embedded-database variant

ePHPm can expose its embedded SQLite-compatible database on the MySQL wire
protocol, but YOURLS's installer declares `keyword varchar(100) CHARACTER
SET utf8mb4 COLLATE utf8mb4_bin` (column-level charset/collation), which
the MySQL → SQLite translation does not handle yet — the installer fails
with `SQLite error: near "SET"`. Tracked in
[`issues/yourls.md`](../../issues/yourls.md); until that lands YOURLS needs
a real MySQL/MariaDB.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release (vendor is committed under `includes/`), copies it onto `ephpm/ephpm` |
| `config.php` | `user/config.php`: environment-driven, official-image variable names |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds the `user` volume, generates the cookie key, waits for the DB, starts `ephpm serve` |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/yourls/test.sh`) |

## Configuration notes

* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and use the `https://` URL in `YOURLS_SITE`.
* Plugins go in the `user` volume (`user/plugins/<name>/plugin.php`) and
  are activated from Admin → Plugins, as usual. OPcache runs with timestamp
  validation off (`ephpm serve` default), so after adding or editing plugin
  PHP run `docker compose exec ephpm ephpm cache reset` or restart.
* YOURLS does not use PHP sessions (login is a signed cookie), so there is
  nothing to move to the KV store.

## Known limitations

* No single-container variant (see above): YOURLS needs a MySQL/MariaDB
  server.
* The embedded `bcmath`-based keyword conversion and everything else YOURLS
  needs is compiled into ePHPm; no optional extension is missing.
