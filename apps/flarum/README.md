# Flarum on ePHPm

| | |
|---|---|
| App | [Flarum](https://flarum.org) 2.0 (`flarum/flarum` skeleton, `FLARUM_VERSION` build arg) with its bundled extensions |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm (the `mondedie/flarum` / `crazymax/flarum` images) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | `compose.sqlite.yml` — Flarum's own SQLite support (pdo_sqlite), not ePHPm's embedded database |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`, `compose.sqlite.yml`): image build, `flarum install` on first start, forum home page, admin login through `/login` (session + CSRF token), a discussion started through the JSON:API and read back from the API and the server-rendered page, `flarum info` on the embedded PHP |

## What changes versus nginx + php-fpm

* **One process.** ePHPm serves `public/` and runs PHP; the skeleton's
  `.nginx.conf` rule (`try_files $uri $uri/ /index.php?$query_string`) is
  `[server] fallback`. `config.php`, `vendor/` and `storage/` sit above the
  web root, as in the skeleton.
* **Installed on first start** with `flarum install` from the environment —
  the variable names of the `mondedie/flarum` image: `FORUM_URL`,
  `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS`, `DB_PREF`,
  `FLARUM_ADMIN_USER`, `FLARUM_ADMIN_PASS`, `FLARUM_ADMIN_MAIL`,
  `FLARUM_TITLE`, plus `DB_DRIVER` (`mariadb` — the default —, `mysql` or
  `sqlite`). On later starts the entrypoint runs `flarum migrate` and
  `flarum cache:clear` (picks up an upgraded image).
* **Use `DB_DRIVER=mariadb` with MariaDB.** With the `mysql` driver on a
  MariaDB server, Flarum 2.0 sends `CAST(? AS JSON)` (MySQL-only syntax) when
  it looks up notifications, and starting a discussion fails with a
  `db_error`. That is Flarum's behaviour on any web server.
* **Volumes:** `/data` (`config.php`, and the SQLite file in the SQLite
  variant), `storage/` (cache, sessions, logs), `public/assets/` (compiled
  CSS/JS, avatars, logo).

## Run

```bash
docker compose up -d                         # MariaDB; or: podman compose up -d
docker compose -f compose.sqlite.yml up -d   # one container, SQLite
open http://localhost:8080                   # EPHPM_PORT=8090 ... — then FORUM_URL=http://localhost:8090 too
```

Log in with `FLARUM_ADMIN_USER` / `FLARUM_ADMIN_PASS` (set a real password
before the first start). `FORUM_URL` must be the address users open the
forum at: links and the session cookie are built from it.

```bash
docker compose exec ephpm flarum info                  # the console (a wrapper for `ephpm php flarum`)
docker compose exec ephpm ephpm php flarum cache:clear
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | `composer create-project flarum/flarum`, onto `ephpm/ephpm`; `php` and `flarum` wrappers |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds the volumes, waits for the database, `flarum install` (first start) or `flarum migrate`, starts `ephpm serve` |
| `compose.yml` | ePHPm + MariaDB |
| `compose.sqlite.yml` | Single container on SQLite |
| `test.sh` | The smoke test CI runs (`bash apps/flarum/test.sh`) |

## Configuration notes

* **Extensions** are Composer packages: add `composer require
  vendor/extension` to the `vendor` stage of the `Dockerfile`, rebuild, then
  enable them in the admin panel. The in-app extension manager is not
  installed.
* **Mail:** configure it in Administration → Email (SMTP); nothing is sent
  until then.
* **Queue:** Flarum's default `sync` queue is kept (jobs run inside the
  request). A Redis-backed queue would need a real Redis (not ePHPm's KV
  store, which is not a broker).
* OPcache runs with timestamp validation off (`ephpm serve` default):
  restart the container after changing PHP files (`ephpm cache reset` is a
  no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* **JPEG/WebP avatars and logos**: ePHPm's GD has no JPEG/WebP support
  (`issues/koel.md`); uploading those formats fails. PNG and GIF work. Not
  exercised by `test.sh`.
* No ePHPm-embedded-database variant: Flarum's own SQLite support already
  gives a single container, without the MySQL-dialect translation gaps.
