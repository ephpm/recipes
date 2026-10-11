# Kanboard on ePHPm

| | |
|---|---|
| App | [Kanboard](https://kanboard.org) v1.2.54 (`KANBOARD_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm + s6 + crond (the `kanboard/kanboard` image) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | `compose.sqlite.yml` — Kanboard's built-in SQLite (its default database, not experimental) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (both variants): admin login, create a project through the form, project list, JSON-RPC `getMyProjects`, `./cli cronjob` + `./cli version` on the embedded PHP, private paths 403 |

## What changes versus the official image

* **One process.** ePHPm serves `/var/www/app` and runs PHP. The nginx
  `try_files $uri $uri/ /index.php$is_args$args` rule is `[server]
  fallback` in `ephpm.toml` (so `ENABLE_URL_REWRITE=true` is set and
  Kanboard emits pretty URLs); the `app/ libs/ vendor/ data/` directories,
  the `cli` script, `config*.php`, plugin PHP files and `*.log` / `*.sqlite`
  are refused with `[server.security] blocked_paths`, as nginx does.
* **Cron on the embedded PHP.** The official image's crontab (`0 8 * * *
  ./cli cronjob`) is a background loop in the entrypoint: `CRON_HOUR`
  (default `8`) picks the hour, empty disables it.
* **`php` on PATH is the embedded CLI**, so `./cli` (`#!/usr/bin/env php`)
  runs as documented: `docker compose exec ephpm ./cli cronjob`.
* **Same environment variables as the official image.** Kanboard's
  `config.default.php` reads them itself: `DB_DRIVER`, `DB_HOSTNAME`,
  `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `DB_SSL_*`,
  `PLUGIN_INSTALLER`, `LOG_DRIVER`, `MAIL_*`, `LDAP_*`, `REVERSE_PROXY_*`,
  `SESSION_HANDLER`, `DEBUG`, … (full list in Kanboard's
  [config docs](https://docs.kanboard.org/v1/admin/config/)).
* No TLS inside the container (the official image generates a self-signed
  certificate for its port 443). Put ePHPm's own `[server.tls]` (ACME or
  cert/key) or a reverse proxy in front.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Log in with `admin` / `admin` and change the password. Kanboard runs its
database migrations on the first request. Plugins installed from the UI
(`PLUGIN_INSTALLER=true`) land in the `plugins` volume; attachments in
`data`.

```bash
docker compose exec ephpm ./cli cronjob          # run the daily job now
docker compose exec ephpm ./cli user:reset-password admin
docker compose restart ephpm                     # after adding/updating plugins (reloads PHP code)
```

### Single container, Kanboard's own SQLite

```bash
docker compose -f compose.sqlite.yml up -d
```

Kanboard's default database (`data/db.sqlite` through `pdo_sqlite`). No
database server, nothing experimental. Back up the `data` volume.

### No ePHPm-embedded-database variant

ePHPm can expose its embedded database on the MySQL wire protocol, but
Kanboard's MySQL driver (PicoDb) wraps its migrations in
`SET FOREIGN_KEY_CHECKS=0` / `=1`, which the MySQL → SQLite translation
passes through to SQLite verbatim (`near "SET": syntax error`), so the
first page is an `Internal Error`; two later migrations (`ALTER DATABASE …
CHARACTER SET`, `ALTER TABLE … CONVERT TO CHARACTER SET`) are rejected as
well. Tracked in [`issues/kanboard.md`](../../issues/kanboard.md). Use
`compose.sqlite.yml` for a single container.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release (vendor is committed), copies it onto `ephpm/ephpm` |
| `ephpm.toml` | Server config: web root, rewrite, blocked private paths, 32 MiB uploads |
| `php` | `php` → `ephpm php` shim for `./cli` |
| `entrypoint.sh` | Waits for the DB, runs the daily cron loop, starts `ephpm serve` |
| `compose.yml`, `compose.sqlite.yml` | The two stacks |
| `test.sh` | The smoke test CI runs (`bash apps/kanboard/test.sh`) |

## Configuration notes

* Attachments: `[server.request] max_body_size` (32 MiB, nginx's
  `client_max_body_size 32M`) and the `upload_max_filesize` /
  `post_max_size` ini overrides move together.
* Sessions: Kanboard's default `SESSION_HANDLER=db` stores sessions in the
  database, so nothing goes to ePHPm's KV store unless you set
  `SESSION_HANDLER=php` **and** add `["session.save_handler", "ephpm"]` to
  `[php] ini_overrides` (untested).
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`,
  and Kanboard's `TRUSTED_PROXY_NETWORKS` / `TRUSTED_PROXY_HEADERS` if you
  use its reverse-proxy authentication.
* OPcache runs with timestamp validation off (`ephpm serve` default): run
  `docker compose restart ephpm` after plugin installs/updates (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`). The official image uses `opcache.jit = tracing`; ePHPm
  keeps the JIT off by default (see its config reference for why).
* `./cli` under `ephpm php` prints `PHP Deprecated: Constant
  PDO::MYSQL_ATTR_INIT_COMMAND is deprecated since 8.5` (from PicoDb) on the
  MariaDB stack — harmless; use the `v0.11.3-php8.4` image tag to silence
  it.

## Known limitations

* `ldap` is not available in the ePHPm build, so `LDAP_AUTH=true` cannot
  be used. Form login, reverse-proxy auth and the API are unaffected.
* `ssmtp`/`mailx` are not in the image: use `MAIL_TRANSPORT=smtp` with the
  `MAIL_SMTP_*` variables rather than the default `mail()`.
* No embedded-database variant (see above).
