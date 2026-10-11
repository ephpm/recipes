# Cachet 3 on ePHPm

| | |
|---|---|
| App | [Cachet](https://cachethq.io) 3.x (`cachethq/cachet` commit `40bd081`, `CACHET_REF` build arg) — Laravel 13 + Filament 5. Cachet 3 has **no tagged release yet**; this recipe pins the 3.x branch head it was tested on |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Cachet's docker image (nginx + php-fpm, supervisord running the scheduler and queue worker) |
| Default stack | `compose.yml` — ePHPm + scheduler + queue worker (same image) + MariaDB 11 |
| Single container | `compose.sqlite.yml` — Cachet's own SQLite file in the storage volume (Cachet's `.env.example` default), no database server. ePHPm's embedded MySQL-compatible database was not attempted |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (MariaDB and native SQLite): migrations + admin user (`cachet:make:user`) by the entrypoint, public status page, dashboard login page with its Filament assets, a Sanctum API token issued on the embedded PHP, a component and an incident created through the REST API and read back from the API and the status page |

## What changes versus Cachet's image

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime; Cachet's nginx `try_files $uri $uri/ /index.php?$query_string`
  is `[server] fallback` in `ephpm.toml`.
* **The scheduler and the queue worker are services**, not supervisord
  programs: `scheduler` runs `artisan schedule:run` every 60 seconds,
  `queue` runs `artisan queue:work` (database queue, Cachet's default) — the
  same image with a different command. Both wait until the web container
  has migrated.
* **Built from source.** The image runs `composer install --no-dev` in a
  `composer:2` stage (`--no-scripts`); the Composer scripts it skips —
  `package:discover`, `vendor:publish --tag=laravel-assets`,
  `vendor:publish --tag=cachet-assets`, `filament:assets` — then run on
  the embedded PHP. `cachethq/core` ships its compiled assets, so there is
  no Node stage.
* **First start:** `APP_KEY` is generated into `storage/.env` (the storage
  volume; `/app/.env` points at it), `artisan migrate --force` runs on
  every start, and the first admin is created once with Cachet's
  `cachet:make:user` from `CACHET_ADMIN_EMAIL` / `CACHET_ADMIN_PASSWORD`.

## Run

```bash
CACHET_ADMIN_EMAIL=you@example.com CACHET_ADMIN_PASSWORD=change-me docker compose up -d
open http://localhost:8080             # the status page
open http://localhost:8080/dashboard   # log in with the admin above
```

Single container, no database server:

```bash
CACHET_ADMIN_EMAIL=you@example.com CACHET_ADMIN_PASSWORD=change-me \
  docker compose -f compose.sqlite.yml up -d
```

`APP_URL` must be the URL users open (default `http://localhost:8080`;
with `EPHPM_PORT` set it to match).

```bash
docker compose exec ephpm ephpm php artisan cachet:make:user          # another user (interactive)
docker compose exec ephpm ephpm php artisan migrate:status
# an API token for a user (the dashboard can issue them too)
docker compose exec ephpm ephpm php artisan tinker --execute \
  'echo \Cachet\Models\User::first()->createToken("cli", ["*"])->plainTextToken;'
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Fetches the pinned source, `composer install`s it, publishes the assets on the embedded PHP |
| `ephpm.toml` | Server config (docroot, fallback, blocked paths, upload limits) |
| `entrypoint.sh` | Seeds the storage volume and `.env`, generates `APP_KEY`, waits for the DB (or creates the SQLite file), migrates, creates the admin once, starts `ephpm serve` (or the given command) |
| `compose.yml` | ePHPm + scheduler + queue + MariaDB |
| `compose.sqlite.yml` | ePHPm + scheduler + queue on Cachet's SQLite file |
| `test.sh` | The smoke test CI runs (`bash apps/cachet/test.sh`), both variants |

## Configuration notes

* PostgreSQL works too as far as Cachet is concerned (`DB_CONNECTION=pgsql`
  and a `postgres` service; ePHPm's PHP has `pdo_pgsql`) — not tested here.
* Sessions and cache use the database (Cachet's defaults).
* `CACHET_BEACON` is set to `false` in both compose files (Cachet's
  anonymous usage beacon). Mail goes to the log (`MAIL_MAILER=log`) until
  you configure SMTP for subscriber notifications.
* Behind a TLS-terminating proxy set `APP_URL` to the public `https://`
  URL and `CACHET_TRUSTED_PROXIES`, plus `[server.security]
  trusted_proxies` in `ephpm.toml`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After changing PHP files run `docker compose restart ephpm`
  (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).

## Known limitations

* Cachet 3 is pre-release upstream; pin `CACHET_REF` deliberately when
  upgrading.
* The Filament dashboard login is a Livewire form; the smoke test checks
  that the login page and its assets are served, but logs in through an
  API token rather than driving Livewire.
* Subscriber e-mail, webhooks and the scheduled checks were not exercised.
