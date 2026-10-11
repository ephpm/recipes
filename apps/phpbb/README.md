# phpBB on ePHPm

| | |
|---|---|
| App | [phpBB](https://www.phpbb.com) 3.3.19 (`PHPBB_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx/Apache + php-fpm (phpBB has no official image; `docs/nginx.sample.conf` is the reference) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | none — not attempted: phpBB supports SQLite 3 natively, but a SQLite variant was not tested for this recipe |
| Status | tested 2026-10-11 on v0.11.3-php8.5: CLI install on first start, admin login, post a topic and read it back in the forum and the Atom feed, `app.php/help/faq` controller route without PATH_INFO, `bin/phpbbcli.php` on the embedded PHP, private paths 403 |

## What changes versus a stock nginx/php-fpm install

* **One process.** ePHPm serves the board's scripts and assets. The nginx
  `try_files $uri $uri/ @rewriteapp` rule is `[server] fallback` ending in
  `/app.php`; the paths `docs/nginx.sample.conf` denies (`config.php`,
  `cache/ files/ includes/ phpbb/ store/ vendor/`, the uploaded avatars)
  are `[server.security] blocked_paths`.
* **Controller routes without `PATH_INFO`.** phpBB's `app.php/help/faq`,
  `app.php/feed`, extension routes … work: ePHPm routes the URL to
  `app.php`, and phpBB's Symfony request derives the route from
  `REQUEST_URI` itself.
* **Installed from the environment.** The first start runs phpBB's CLI
  installer (`install/phpbbcli.php install`) with a config generated from the
  `PHPBB_*` variables, keeps the resulting `config.php` in the `state`
  volume, and removes `install/` (phpBB refuses to serve while it exists).
  There is no web installer step.
* **Built from the release tag.** `download.phpbb.com` refuses non-browser
  clients, so the Dockerfile takes the GitHub `release-<version>` archive
  and installs `vendor/` with Composer (the release package has it
  pre-installed; the result is the same `composer.lock`).
* **`php` on PATH is the embedded CLI**, so `bin/phpbbcli.php` runs as
  documented.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 ... — then set PHPBB_SERVER_PORT=8090 too
```

Log in as `PHPBB_ADMIN_USER` / `PHPBB_ADMIN_PASS` (`admin` /
`phpbb-admin-password` by default — change them in `compose.yml` or a
`.env` file). `PHPBB_SERVER_PROTOCOL/NAME/PORT` (and `PHPBB_SCRIPT_PATH`)
seed the board's cookie/URL settings; change them later in the ACP.

```bash
docker compose exec ephpm php bin/phpbbcli.php cache:purge
docker compose exec ephpm php bin/phpbbcli.php extension:enable vendor/name
docker compose exec ephpm php bin/phpbbcli.php config:get sitename
docker compose restart ephpm                      # after installing extensions/styles (reloads PHP code)
```

Variables (first start only, except the DB ones): `PHPBB_DB_HOST`,
`PHPBB_DB_NAME`, `PHPBB_DB_USER`, `PHPBB_DB_PASSWORD`,
`PHPBB_TABLE_PREFIX`, `PHPBB_ADMIN_USER`, `PHPBB_ADMIN_PASS`,
`PHPBB_ADMIN_EMAIL`, `PHPBB_BOARD_NAME`, `PHPBB_BOARD_DESCRIPTION`,
`PHPBB_BOARD_LANG`, `PHPBB_SERVER_PROTOCOL`, `PHPBB_SERVER_NAME`,
`PHPBB_SERVER_PORT`, `PHPBB_SCRIPT_PATH`, `PHPBB_COOKIE_SECURE`.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | GitHub release archive + `composer install`, copied onto `ephpm/ephpm`, pristine copies to seed the volumes |
| `ephpm.toml` | Server config: `app.php` fallback, nginx-equivalent blocked paths, 32 MiB uploads |
| `php` | `php` → `ephpm php` shim for `bin/phpbbcli.php` |
| `entrypoint.sh` | Seeds volumes, waits for the DB, CLI install on first start, removes `install/`, starts `ephpm serve` |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/phpbb/test.sh`) |

## Configuration notes

* Volumes: `state` (`config.php`), `ext` (extensions), `files`
  (attachments), `store`, `avatars` (uploaded avatars). Styles live in the
  image (`styles/`); add them in the Dockerfile.
* Attachments: `[server.request] max_body_size` (32 MiB) and the
  `upload_max_filesize` / `post_max_size` ini overrides move together with
  the ACP attachment limits.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and `PHPBB_SERVER_PROTOCOL=https://` / cookie secure in the ACP.
* Cron: phpBB runs its tasks on page views (`cron.php`) by default; for
  the system cron mode run `php bin/phpbbcli.php cron:run` from a host
  cron or an extra compose service.
* OPcache runs with timestamp validation off (`ephpm serve` default): run
  `docker compose restart ephpm` after installing extensions or styles (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* No single-container variant (see the table).
* E-mail is disabled by the installer config (`email.enabled: false`);
  configure SMTP in the ACP (Client communication → Email settings).
* `imagick` is not available; phpBB resizes with GD.
