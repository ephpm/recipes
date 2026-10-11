# FreshRSS on ePHPm

| | |
|---|---|
| App | [FreshRSS](https://freshrss.org) 1.30.1 (`FRESHRSS_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php + crond (the `freshrss/freshrss` images) |
| Default stack | `compose.yml` — ePHPm + PostgreSQL 17 (what FreshRSS's own compose example uses) |
| Single container | `compose.sqlite.yml` — FreshRSS's built-in SQLite (its default database, not experimental) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (both variants): CLI auto-install + admin user, web login, create a category, Fever API, CLI scripts, feed refresh returns, session in the KV store — with the `dns_get_record()` polyfill described below |

> **Read this first.** On ePHPm v0.11.3 PHP's `dns_get_record()` never
> returns, and FreshRSS calls it on every feed add and refresh. The recipe
> ships a small polyfill (`dns-polyfill.php`, loaded through `disable_functions`
> + `auto_prepend_file`) so feeds work; it only answers A/AAAA lookups, which
> is all FreshRSS needs. Details and the ePHPm-side fix in
> [`issues/freshrss.md`](../../issues/freshrss.md). Remove the polyfill and
> the two ini lines once ePHPm is fixed.

## What changes versus the official image

* **One process.** ePHPm serves FreshRSS's `p/` directory and runs PHP; the
  nginx reference `try_files $uri $uri/ index.php` is `[server] fallback` in
  `ephpm.toml`. There is no Apache, no `.htaccess`.
* **Cron on the embedded PHP.** `CRON_MIN="2,32"` (same variable as the
  official image) runs `app/actualize_script.php` through `ephpm php` at
  those minutes, from a background loop in the entrypoint — no crond.
* **Sessions in the KV store.** `session.save_handler = ephpm` keeps PHP
  sessions in ePHPm's in-process store instead of files under `/tmp`. They do
  not survive a restart (neither did the files); FreshRSS's "keep me logged
  in" cookie re-logs you.
* **`php` on PATH is the embedded CLI.** FreshRSS's `cli/*.php` scripts have
  `#!/usr/bin/env php` shebangs and run exactly as documented:
  `docker compose exec ephpm cli/list-users.php`.
* **Same environment variables as the official image** — `TZ`, `CRON_MIN`,
  `FRESHRSS_ENV`, `FRESHRSS_INSTALL`, `FRESHRSS_USER`, `DATA_PATH`,
  `INTERNAL_HOST_ALLOWLIST`. Not applicable here: `LISTEN`,
  `ENABLE_ACCESS_LOG`, `COPY_LOG_TO_SYSLOG`, `COPY_SYSLOG_TO_STDERR` (Apache
  and syslog settings — ePHPm logs to stdout/stderr; `[server.logging] access`
  gives a JSON access log), `TRUSTED_PROXY` (use `[server.security]
  trusted_proxies`), `OIDC_*` (needs Apache's `mod_auth_openidc`).

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

`compose.yml` installs FreshRSS and creates the `admin` user on the first
start from `FRESHRSS_INSTALL` / `FRESHRSS_USER` (`cli/do-install.php` and
`cli/create-user.php` arguments, exactly like the official image). Put
`ADMIN_PASSWORD`, `ADMIN_API_PASSWORD`, `ADMIN_EMAIL` in a `.env` file to
change the defaults (`freshrss` / `freshrss` / `admin@example.net`). Delete
`FRESHRSS_INSTALL` from the compose file to use the web installer at `/i/`
instead.

```bash
docker compose exec ephpm cli/list-users.php
docker compose exec ephpm cli/create-user.php --user alice --password 's3cret'
docker compose exec ephpm cli/actualize-user.php --user admin     # refresh now
docker compose exec ephpm ephpm kv keys 'session:*'               # live sessions
```

### Single container, FreshRSS's own SQLite

```bash
docker compose -f compose.sqlite.yml up -d
```

FreshRSS's default database: one SQLite file per user in the `data` volume,
through `pdo_sqlite`. No database server, nothing experimental.

### No ePHPm-embedded-database variant

ePHPm can serve its embedded database on the MySQL wire protocol, and
`cli/do-install.php --db-type mysql --db-host 127.0.0.1:3306` does get past
the install step — but `cli/create-user.php` fails: FreshRSS's per-user
MySQL schema declares `url VARCHAR(32768) CHARACTER SET latin1 COLLATE
latin1_bin` and friends, and litewire does not translate column-level
charset/collation clauses yet (`issues/yourls.md` has the stock-image
repro). Use `compose.sqlite.yml` for a single container.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release, trims development files, copies it onto `ephpm/ephpm` |
| `ephpm.toml` | Server config |
| `dns-polyfill.php` | Userland `dns_get_record()` over getaddrinfo (ePHPm workaround, see above) |
| `php` | `php` → `ephpm php` shim (with the same workaround flags) |
| `entrypoint.sh` | `TZ` into php.ini, `cli/prepare.php`, first-run install/user, `CRON_MIN` loop, `ephpm serve` |
| `compose.yml`, `compose.sqlite.yml` | The two stacks |
| `test.sh` | The smoke test CI runs (`bash apps/freshrss/test.sh`) |

## Configuration notes

* `TZ` becomes `date.timezone` (the entrypoint writes `/run/ephpm/php.ini`,
  loaded through `[php] ini_file`).
* Uploads/imports: `[server.request] max_body_size` (32 MiB, as the official
  image) and the `upload_max_filesize` / `post_max_size` ini overrides move
  together.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  (replaces the image's `TRUSTED_PROXY`) and pass `--base-url https://…` in
  `FRESHRSS_INSTALL` (or edit `data/config.php`).
* OPcache runs with timestamp validation off (`ephpm serve` default). After
  changing PHP files in the container (extensions in the `extensions` volume
  included) run `docker compose exec ephpm ephpm cache reset` or restart.
* `disable_update` is forced on in `config.default.php`, as in the official
  image: update the image, not the app from its UI.

## Known limitations

* **Google Reader API clients do not work.** `/api/greader.php/reader/api/0/…`
  needs `PATH_INFO` (`fastcgi_split_path_info` in FreshRSS's nginx config);
  ePHPm's router has no `script.php/extra` splitting and routes those URLs to
  `index.php`. The **Fever API** (`/api/fever.php`, query-string based) works
  and is what the smoke test uses. See `issues/freshrss.md`.
* `dns_get_record()` is replaced by the recipe's polyfill (A/AAAA only). A
  FreshRSS extension that needs MX/TXT lookups will get an empty answer.
* `OIDC_ENABLED` (Apache `mod_auth_openidc`) and `--auth-type http_auth`
  (Apache access control) have no equivalent here; use the form login.
* Sessions and the KV store are in memory: a restart logs everyone out
  (the "keep me logged in" cookie covers that).
