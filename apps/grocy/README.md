# Grocy on ePHPm

| | |
|---|---|
| App | [Grocy](https://grocy.info) 4.7.1 (`GROCY_VERSION` build arg; requires PHP 8.5) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `linuxserver/grocy` image (nginx + php-fpm + s6) |
| Default stack | `compose.yml` — one container; Grocy's own SQLite database in the data volume |
| Single container | that is the default |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, schema migration on the first request, login as `admin` through the login form, stock overview page, a location created through the REST API (session-authenticated, as the web UI does) and read back from the API and the Locations page, API refused (401) and UI redirected without a session |

## What changes versus the linuxserver image

* **One process.** ePHPm serves `public/` and runs PHP; `public/.htaccess`
  (`RewriteRule ^ index.php`) is `[server] fallback`. The application code
  and `data/` sit above the web root, so nothing else needs blocking.
* **The release zip is used as is** (it ships `packages/` — Grocy's
  Composer and front-end dependencies).
* **`data/` is the volume** (`grocy.db`, `config.php`, uploaded files,
  view cache), seeded on first start: `config.php` is copied from
  `config-dist.php`, as the linuxserver image does.
* **Settings from the environment**: Grocy itself reads any setting from
  `config-dist.php` as `GROCY_<SETTING>` (`GROCY_CULTURE`, `GROCY_CURRENCY`,
  `GROCY_BASE_URL`, `GROCY_FEATURE_FLAG_…`, …) — the same variables the
  linuxserver image documents. Editing `data/config.php` works too.
* Grocy migrates its database on its root route: the first visit to `/`
  creates `grocy.db`.

## Run

```bash
docker compose up -d                # or: podman compose up -d
open http://localhost:8080          # EPHPM_PORT=8090 docker compose up -d to change
```

Log in with `admin` / `admin` and change the password (Settings → Users).
For the REST API create a key under Settings → Manage API keys and send it
as the `GROCY-API-KEY` header; the API is documented at `/api`.

There is no Grocy CLI; `docker compose exec ephpm ephpm php -r '…'` runs
one-off PHP against the same files if you need it.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release zip, onto `ephpm/ephpm` |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds `data/` (and `config.php`), starts `ephpm serve` |
| `compose.yml` | The single-container stack |
| `test.sh` | The smoke test CI runs (`bash apps/grocy/test.sh`) |

## Configuration notes

* Behind a reverse proxy on a sub-path or another host name set
  `GROCY_BASE_URL` (and `[server.security] trusted_proxies` in `ephpm.toml`).
* Upgrading: bump `GROCY_VERSION` and rebuild; the next visit to `/`
  migrates the database. Back up `data/grocy.db` first.

## Known limitations

* **Pictures**: ePHPm's GD has no JPEG/WebP support (`issues/koel.md`), so
  product/recipe pictures in those formats cannot be resized for display
  (Grocy resizes with GD); PNG and GIF work. Not exercised by `test.sh`.
* Barcode-scanner and label-printer features that talk to local devices work
  the same as on any server (they run in the browser or call configured
  webhooks); they are not tested here.
