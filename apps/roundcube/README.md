# Roundcube Webmail on ePHPm

| | |
|---|---|
| App | [Roundcube](https://roundcube.net) 1.7.4 (`ROUNDCUBE_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the `roundcube/roundcubemail` image) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 + a throwaway test mail server (GreenMail) |
| Single container | `compose.sqlite.yml` — Roundcube's own SQLite database (its default; not experimental) + the test mail server |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (MariaDB and SQLite): login against the test IMAP server, mailbox opens, skin assets via `static.php`, save a contact and export it as vCard, `bin/cleandb.sh` on the embedded PHP, nothing outside `public_html/` reachable |

Roundcube is an IMAP client: it needs **your** mail server. Both compose
files include `mail`, an in-memory GreenMail that accepts any login and
keeps nothing, so the stack runs — and is smoke-tested — out of the box.
Point `ROUNDCUBEMAIL_DEFAULT_HOST` / `ROUNDCUBEMAIL_SMTP_SERVER` (and the
ports) at your real server and delete the `mail` service.

## What changes versus the official image

* **One process.** ePHPm serves `public_html/` — the web root Roundcube 1.7
  requires (`index.php` plus `static.php`, the endpoint that serves skin and
  plugin assets from outside the web root). Asset URLs look like
  `/static.php/skins/elastic/…`; Apache resolves them with `PATH_INFO`,
  ePHPm has none, but `static.php` falls back to parsing `REQUEST_URI`, so
  `[server] fallback` routes every non-file URL to it. Nothing outside
  `public_html/` is reachable.
* **Same environment variables as the official image.**
  `ROUNDCUBEMAIL_DB_TYPE` (`mysql` | `pgsql` | `sqlite`),
  `ROUNDCUBEMAIL_DB_HOST/PORT/USER/PASSWORD/NAME`,
  `ROUNDCUBEMAIL_DEFAULT_HOST/PORT` (IMAP), `ROUNDCUBEMAIL_SMTP_SERVER/PORT`,
  `ROUNDCUBEMAIL_USERNAME_DOMAIN`, `ROUNDCUBEMAIL_PLUGINS`,
  `ROUNDCUBEMAIL_SKIN`, `ROUNDCUBEMAIL_REQUEST_PATH`, `ROUNDCUBEMAIL_DES_KEY`.
  Not supported: `ROUNDCUBEMAIL_COMPOSER_PLUGINS` (no Composer in the
  image — add plugins in the Dockerfile) and `ROUNDCUBEMAIL_ASPELL_DICTS`
  (no `pspell`; the spellchecker is off unless you configure another
  engine). `config.inc.php` is regenerated from the environment at every
  start; your own settings go into `/var/roundcube/config/*.php` (the
  volume), which it includes — same as the official image's
  `/var/roundcube/config`.
* **`php` on PATH is the embedded CLI**, so `bin/*.sh` run as documented
  (`bin/initdb.sh` runs at every start, as in the official image).
* The `des_key` not given is generated once into the `state` volume.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

With the bundled test mail server, log in with any address and any
password (e.g. `alice@example.com`). With your own server, use your
mailbox credentials.

```bash
docker compose exec ephpm bin/cleandb.sh                 # Roundcube's cron job
docker compose exec ephpm bin/gc.sh
docker compose exec ephpm ephpm cache reset              # after editing PHP / adding plugins
```

### Single container, Roundcube's own SQLite

```bash
docker compose -f compose.sqlite.yml up -d
```

Roundcube's default database (`/var/roundcube/db/sqlite.db` in the `state`
volume). Fine for personal use.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the "complete" release (vendor + plugins), copies it onto `ephpm/ephpm` |
| `ephpm.toml` | Server config: `public_html/` web root, `static.php` fallback, 25 MiB uploads |
| `php` | `php` → `ephpm php` shim for `bin/*.sh` |
| `entrypoint.sh` | Generates `config.inc.php` from the environment, waits for the DB, `bin/initdb.sh --update`, `ephpm serve` |
| `compose.yml`, `compose.sqlite.yml` | The two stacks |
| `test.sh` | The smoke test CI runs (`bash apps/roundcube/test.sh`) |

## Configuration notes

* Attachments: `[server.request] max_body_size` (25 MiB) and the
  `upload_max_filesize` / `post_max_size` ini overrides move together
  (the official image's `ROUNDCUBEMAIL_UPLOAD_MAX_FILESIZE` maps to these).
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`;
  Roundcube's `request_path` config covers a sub-path deployment.
* Roundcube's housekeeping (`bin/cleandb.sh`, `bin/gc.sh`) is not
  scheduled; run it from a host cron or an extra compose service.
* Sessions are Roundcube's own (`session_storage = db`), not PHP file
  sessions, so nothing is moved to the KV store.

## Known limitations

* No `pspell` (spellchecker off by default) and no `ldap` (LDAP address
  books cannot be used) in the ePHPm build.
* No Composer-based plugin installation at runtime (see above).
