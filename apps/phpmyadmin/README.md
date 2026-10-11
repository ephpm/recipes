# phpMyAdmin on ePHPm

| | |
|---|---|
| App | [phpMyAdmin](https://www.phpmyadmin.net) 5.2.3 (`PMA_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the `phpmyadmin:apache` image) |
| Default stack | `compose.yml` — ePHPm + a MariaDB 11 to manage (point `PMA_HOST` elsewhere to manage yours) |
| Single container | n/a — phpMyAdmin stores nothing; it is one container either way |
| Status | tested 2026-10-11 on v0.11.3-php8.5: cookie-auth login to the MariaDB, create a database from the Databases page, see it listed and on the server, session in the KV store, PHP-only paths 403 — **with the `ResponseRenderer` patch described below** |

> **Read this first.** phpMyAdmin renders every page from a shutdown
> function that ends in `exit;`, and ePHPm v0.11.3 reports an `exit()`
> inside a shutdown function as a crash: every page is a 500 with the
> finished HTML thrown away. The Dockerfile rewrites that one `exit;` to
> `return;` (build fails loudly if a newer phpMyAdmin moves the line).
> Details, a stock-image repro and the ePHPm-side fix are in
> [`issues/phpmyadmin.md`](../../issues/phpmyadmin.md). Drop the patch once
> ePHPm is fixed.

## What changes versus the official image

* **One process.** ePHPm serves the files and runs PHP. phpMyAdmin needs no
  rewrites (`index.php?route=…`), so `[server] fallback` ends in `=404`;
  `libraries/ templates/ vendor/ sql/ tmp/` are refused with `[server.security]
  blocked_paths`.
* **Same environment variables as the official image.** `PMA_HOST` /
  `PMA_HOSTS`, `PMA_PORT(S)`, `PMA_VERBOSE(S)`, `PMA_SOCKET(S)`, `PMA_USER` +
  `PMA_PASSWORD` (auto-login), `PMA_ARBITRARY`, `PMA_ABSOLUTE_URI`,
  `PMA_PMADB` + `PMA_CONTROLHOST/PORT/USER/PASS`, `PMA_QUERYHISTORYDB/MAX`,
  `PMA_UPLOADDIR`, `PMA_SAVEDIR`, `PMA_SSL*` (incl. the `*_BASE64` forms),
  `MAX_EXECUTION_TIME`, `MEMORY_LIMIT`, `UPLOAD_LIMIT`, `TZ`,
  `HIDE_PHP_VERSION`, `PMA_CONFIG_BASE64`, `PMA_USER_CONFIG_BASE64`, and the
  `*_FILE` secret variants. The bundled `config.inc.php` follows the official
  one; `config.user.inc.php` and `conf.d/*.php` under `/etc/phpmyadmin` are
  included the same way.
* **Sessions in the KV store.** `session.save_handler = ephpm` replaces the
  official image's `/sessions` directory. Sessions do not survive a restart
  (log in again).
* **The cookie-auth secret** (`blowfish_secret`) is generated per container
  start unless `/etc/phpmyadmin/config.secret.inc.php` is mounted or
  `PMA_BLOWFISH_SECRET` is set — same as the official image.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Log in with `root` / `root` (the `db` service's `MARIADB_ROOT_PASSWORD`).
To manage an existing server, delete the `db` service and set
`PMA_HOST` (and `PMA_PORT`), or `PMA_HOSTS=db1,db2` for several.

```bash
docker compose exec ephpm ephpm kv keys 'session:*'   # live sessions
docker compose restart ephpm                           # after editing PHP in the container (reloads PHP code)
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release, trims the setup wizard/examples (as the official image), points `vendor_config.php` at `/etc/phpmyadmin`, applies the `ResponseRenderer` patch |
| `config.inc.php` | `/etc/phpmyadmin/config.inc.php`: environment-driven, official-image variable names |
| `ephpm.toml` | Server config: 64 MiB bodies, 660 s request deadline, KV sessions, blocked PHP-only paths |
| `entrypoint.sh` | `UPLOAD_LIMIT`/`TZ`/`HIDE_PHP_VERSION` into php.ini, cookie secret, `PMA_*_BASE64` configs, `ephpm serve` |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/phpmyadmin/test.sh`) |

## Configuration notes

* Imports: `UPLOAD_LIMIT` (default `2048K` as the official image; `64M` in
  `compose.yml`) sets `upload_max_filesize`/`post_max_size`; raise
  `[server.request] max_body_size` in `ephpm.toml` alongside it.
* `[php] max_execution_time = 600` and `[server.timeouts] request = 660`:
  ePHPm warns (and PHP's own timeout can never fire) if the request
  deadline is not above `max_execution_time`.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and `PMA_ABSOLUTE_URI`.
* The configuration storage (`PMA_PMADB` + control user) works as with the
  official image; create the `phpmyadmin` database with phpMyAdmin's
  `sql/create_tables.sql` first.

## Known limitations

* The `ResponseRenderer` patch is an ePHPm workaround, not an upstream
  change (see the note at the top).
* `bz2` imports are supported (`bz2` is compiled in); the official image's
  `uploadprogress` extension is not, so there is no upload progress bar.
* `imagick` is unavailable; nothing in phpMyAdmin needs it.
