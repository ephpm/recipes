# Adminer on ePHPm

| | |
|---|---|
| App | [Adminer](https://www.adminer.org) 6.1.2 (`ADMINER_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | `php -S` (the official `adminer` image serves itself with PHP's built-in web server) |
| Default stack | `compose.yml` — ePHPm + a MariaDB 11 to manage (point `ADMINER_DEFAULT_SERVER` elsewhere to manage yours) |
| Single container | n/a — Adminer stores nothing; it is one container either way |
| Status | tested 2026-10-11 on v0.11.3-php8.5: login to the MariaDB through the form, create a database from the form, see it listed and on the server, `ADMINER_DESIGN` CSS served and an `ADMINER_PLUGINS` stub generated, session in the KV store, PHP sources 403 |

## What changes versus the official image

* **A real web server.** ePHPm serves `index.php` (the plugin-loading front
  controller), `adminer.css` and nothing else; `adminer.php` itself,
  `plugins/`, `plugins-enabled/` and the loader are refused with
  `[server.security] blocked_paths`. The official image runs `php -S`.
* **Same environment variables as the official image.**
  `ADMINER_DEFAULT_SERVER` (prefilled "Server" field, default `db`),
  `ADMINER_DESIGN` (a theme from `designs/`), `ADMINER_PLUGINS`
  (space-separated names from `plugins/`; a plugin whose constructor needs
  arguments must be enabled by hand with a `plugins-enabled/<name>.php`
  stub, exactly as with the official image).
* **Sessions in the KV store.** Adminer keeps the login state and its CSRF
  token in `$_SESSION`; `session.save_handler = ephpm` stores that in ePHPm's
  in-process store instead of files. A restart logs everyone out.
* All of Adminer's drivers are present except what needs extensions ePHPm
  lacks: MySQL/MariaDB, PostgreSQL and SQLite work (`mysqli`, `pdo_pgsql`,
  `pdo_sqlite` / `sqlite3` are compiled in); MS SQL, Oracle, MongoDB and
  ODBC are not available (`pdo_dblib`/`sqlsrv`, `oci8`, `mongodb` ext,
  `pdo_odbc` are not in the ePHPm build).

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Log in with system `MySQL`, server `db`, `root` / `root` (the `db`
service's `MARIADB_ROOT_PASSWORD`). To manage an existing server, delete
the `db` service and set `ADMINER_DEFAULT_SERVER=host[:port]`.

```bash
ADMINER_DESIGN=hever ADMINER_PLUGINS="tables-filter dump-zip" docker compose up -d
# designs: the directories under designs/ that contain an adminer.css
# (hever, flat, nette, pepa-linha, …); dracula ships adminer-dark.css only
docker compose exec ephpm ephpm kv keys 'session:*'   # live sessions
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads `adminer-<version>.php` plus `designs/` and `plugins/` from the source tarball, like the official image |
| `index.php` | Front controller: loads `plugins-enabled/*.php`, prefills the server field, runs `adminer.php` |
| `plugin-loader.php` | Generates a `plugins-enabled/` stub for a plugin name (`ADMINER_PLUGINS`) |
| `ephpm.toml` | Server config: 128 MiB dump uploads, 660 s request deadline, KV sessions, blocked PHP paths |
| `entrypoint.sh` | `ADMINER_DESIGN` symlink, `ADMINER_PLUGINS` stubs, `ephpm serve` |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/adminer/test.sh`) |

## Configuration notes

* Dump uploads: `UPLOAD` size is `[server.request] max_body_size` (128 MiB,
  the official image's `upload_max_filesize`) plus the matching ini
  overrides; `max_execution_time = 600` and `[server.timeouts] request =
  660` (the request deadline must exceed PHP's own timeout).
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`.
* Editor (`editor-<version>.php`) is not bundled; swap the download URL in
  the Dockerfile to run Adminer Editor instead.

## Known limitations

* No MS SQL / Oracle / MongoDB / ODBC drivers (see above).
