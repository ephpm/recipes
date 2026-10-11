# Symfony on ePHPm

| | |
|---|---|
| App | [Symfony Demo](https://github.com/symfony/demo) v2.9.0 (Symfony 8 blog: Doctrine, security, forms, AssetMapper) — `DEMO_VERSION` build arg |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm, the Symfony CLI server, FrankenPHP |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | `compose.sqlite.yml` — the demo's own SQLite database (pdo_sqlite is compiled into ePHPm); not experimental |
| Embedded ePHPm DB | not offered — Doctrine's MySQL schema tool emits `ALTER TABLE … ADD CONSTRAINT … FOREIGN KEY`, which ePHPm's embedded database rejects (see `issues/symfony.md`) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`, `compose.sqlite.yml`): schema + fixtures on first start, blog renders, login as `jane_admin` through the CSRF-protected form, a post created through the admin form is listed in the admin and found by the public search |

This recipe builds the official demo so it is testable on its own. For your
application replace the `composer create-project` line in the `Dockerfile`
with `COPY . /app` + `composer install`, and drop the fixtures step from
`entrypoint.sh`.

## What changes versus nginx + php-fpm

* **One process.** `[server] fallback = ["$uri", "/index.php?$query_string"]`
  in `ephpm.toml` is nginx's `try_files $uri /index.php$is_args$args`;
  `document_root` is `public/`.
* **Composer scripts run at build time** in the `composer:2` stage (the
  demo's `importmap:install`, `sass:build`, `assets:install`), so the final
  image needs no node and no second PHP. `cache:warmup` runs on the embedded
  PHP in the final stage.
* **Console on the embedded PHP:** `docker compose exec ephpm ephpm php bin/console ...`.
* **First start** creates the schema and loads the demo fixtures
  (`entrypoint.sh`) if the user table is empty. The fixtures bundle is
  dev-only, so that step runs with `--env=dev`; the server itself runs
  `APP_ENV=prod`.
* **Sessions/cache in the KV store (optional).** `ephpm.toml` enables the
  loopback RESP listener; point `framework.session.handler_id` or a cache
  pool at `redis://127.0.0.1:6379` (with `predis/predis` or the `redis`
  extension from ePHPm's extension catalog) to drop a Redis container.

## Run

```bash
docker compose up -d                       # MariaDB
docker compose -f compose.sqlite.yml up -d # single container, SQLite
open http://localhost:8080                 # jane_admin / kitten
```

## Environment

Standard Symfony variables: `APP_ENV`, `APP_SECRET` (**change it**),
`DATABASE_URL`, `MAILER_DSN`, `DEFAULT_URI`, `TRUSTED_PROXIES`. No `.env.local`
is baked into the image; real environment variables win over `.env`.

| Variable | Default | Purpose |
|---|---|---|
| `EPHPM_CONFIG` | `/etc/ephpm/ephpm.toml` | ePHPm config file to serve with |
| `DATABASE_URL` | `sqlite:////app/data/database.sqlite` | Doctrine DSN; `compose.yml` points it at MariaDB |

## Configuration notes

* `curl`-style clients: Symfony 7.2+ stateless CSRF (`stateless_token_ids`)
  accepts a same-origin `Origin`/`Referer` header when the JS double-submit
  cookie is absent — browsers always send one; `test.sh` adds it explicitly.
* After deploying new code run `docker compose restart ephpm`; ePHPm's `serve` mode keeps
  OPcache timestamp validation off (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).
* The `[server.security]` sandbox flags are set `false` explicitly (they act
  only in ePHPm's multi-tenant mode); `blocked_paths` keeps `/var`, `/vendor`,
  `/config` and `.env*` off the web.

## Known limitations

* No ePHPm-embedded-database variant: Doctrine's MySQL platform adds foreign
  keys with `ALTER TABLE … ADD CONSTRAINT`, which the embedded engine rejects
  (`SQLite error: near "CONSTRAINT"`). Use `compose.sqlite.yml` for a single
  container instead.
* Worker mode is not used: a Symfony Runtime adapter for ePHPm is planned,
  not shipped.
