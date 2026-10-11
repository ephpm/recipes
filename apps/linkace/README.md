# LinkAce on ePHPm

| | |
|---|---|
| App | [LinkAce](https://www.linkace.org) 2.6.2 (`LINKACE_VERSION` build arg) — Laravel 11 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `linkace/linkace` image (Caddy + php-fpm + supervisord) and its Redis service; Meilisearch is optional upstream and not used here |
| Default stack | `compose.yml` — ePHPm + scheduler sidecar + MariaDB 11 |
| Single container | not offered — LinkAce installs from a MySQL schema dump the embedded database cannot load (see `issues/linkace.md`) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, setup wizard (requirements, database + migrations, admin account), login through the login form, add a bookmark through the web form and read it back, `artisan schedule:run` inside the scheduler service |

## What changes versus the official image

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime; there is no Caddy, no php-fpm socket and no supervisord. Laravel's
  front-controller routing comes from `[server] fallback` in `ephpm.toml`.
* **The release zip is used as-is.** LinkAce's GitHub release ships
  `vendor/` and the built Vite assets, so the image has no Composer or Node
  stage — it downloads the zip and copies it onto `ephpm/ephpm`. The only
  package added is `mariadb-client`: LinkAce ships a pruned migration set
  plus a schema dump, which Laravel loads through the `mysql` CLI (the
  official base image installs the client for the same reason).
* **Same environment variables as the official image.** `APP_URL`,
  `TRUSTED_PROXIES`, `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`,
  `DB_USERNAME`, `DB_PASSWORD`, `REDIS_*`, `APP_SEARCH_DRIVER`, `MAIL_*`, …
  — anything LinkAce reads from `.env` can be set in `environment:` and
  wins over the `.env` file.
* **`.env` lives in the `linkace-storage` volume** (`storage/.env`, with
  `/app/.env` pointing at it), the way the official compose file bind-mounts
  `./.env`. The entrypoint seeds it from `env.template` and generates
  `APP_KEY` once; the setup wizard writes the database settings into it.
* **The scheduler is a second container from the same image** running
  `ephpm php artisan schedule:run` every minute. LinkAce drives its queue
  (link checks, imports, Internet Archive backups, notifications) from the
  scheduler, which upstream asks you to run from cron; the official image
  does not include one.
* **Cache and sessions** use Laravel's `file` driver by default, as upstream
  does without Redis. To put them in ePHPm's in-process KV store instead of
  running a Redis service, set `CACHE_DRIVER=redis`, `SESSION_DRIVER=redis`
  and `REDIS_HOST=127.0.0.1` (predis ships with LinkAce; the RESP listener is
  enabled in `ephpm.toml`). Not exercised by `test.sh`.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

`APP_URL` must be the address you open LinkAce at (default
`http://localhost:8080`): its `TrustHosts` middleware answers **400 Bad
Request** to any other `Host` header. Either `APP_URL=http://links.example.com
docker compose up -d` or set `TRUSTED_HOSTS` (comma-separated) in
`environment:`.

The setup wizard appears on first visit. On the database step enter the
values from `compose.yml` — type MySQL, host `db`, port `3306`, database
`linkace`, user `linkace`, password `linkace` — then create the admin account.

Afterwards:

```bash
docker compose exec ephpm ephpm php artisan links:check     # any artisan command
docker compose exec ephpm ephpm php artisan schedule:run    # what the scheduler service runs every minute
docker compose exec ephpm ephpm kv keys '*'                 # the live KV store (with the redis drivers above)
docker compose logs ephpm                                    # PHP errors and ePHPm's log
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the LinkAce release zip, adds `mariadb-client`, copies the app onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `env.template` | Seed for `storage/.env` (official variable names) |
| `entrypoint.sh` | Seeds the storage volume and `.env`, generates `APP_KEY`, waits for the DB, starts `ephpm serve` (or runs the given command) |
| `compose.yml` | The stack: ePHPm, scheduler, MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/linkace/test.sh`) |

## Configuration notes

* Uploads/imports: `[server.request] max_body_size` (20 MiB) and the
  `upload_max_filesize` / `post_max_size` ini overrides move together
  (the official `php.ini` uses 20M too).
* `error_reporting` excludes deprecations, as in the official image; PHP
  errors go to the container log (`display_errors` is off under
  `ephpm serve`).
* Behind a TLS-terminating proxy keep `TRUSTED_PROXIES=*` (the official
  default; or the proxy's IP) so LinkAce honours `X-Forwarded-*`, and set
  `APP_URL` to the public `https://` URL.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After changing PHP files inside a running container run
  `docker compose exec ephpm ephpm cache reset` or restart it — the loopback
  RESP listener in `ephpm.toml` exists for that.
* Search uses LinkAce's built-in database search (`APP_SEARCH_DRIVER=database`).
  Meilisearch/Typesense work as upstream documents if you add the service and
  the `MEILISEARCH_*` variables.
* The wizard can also be skipped from the CLI with LinkAce's own commands:
  `docker compose exec ephpm ephpm php artisan migrate --force`, then
  `... artisan registeruser <name> <email> <password> --admin` and
  `... artisan setup:complete` — not exercised by `test.sh`.

## Known limitations

* **No single-container variant.** LinkAce's install path loads
  `database/schema/mysql-schema.dump` (MariaDB-dump DDL: `DEFAULT
  current_timestamp()`, `COLLATE utf8mb4_bin`), which ePHPm's embedded
  MySQL-compatible database rejects on the first table. Details and a
  minimal repro in `issues/linkace.md`.
* `ext-ldap`/`imagick` are not in the ePHPm build; LinkAce needs neither
  (it checks `bcmath ctype curl dom fileinfo filter hash json mbstring openssl
  pcre session tokenizer xml pdo_mysql`, all present).
