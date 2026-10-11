# Yii 2 on ePHPm

| | |
|---|---|
| App | [Yii 2](https://www.yiiframework.com) basic application template `yiisoft/yii2-app-basic` 2.0.54 (`YII_VERSION` build arg), framework 2.0.55 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the `yiisoftware/yii2-php` apache image), or nginx + php-fpm |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | none — the embedded database cannot run `yii migrate` (see `issues/yii2.md`) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, `yii migrate` on start, home page, Yii's 404 page for an unknown route, login as `admin` through the CSRF-protected form, a POST without the CSRF token refused with 400 |

## What changes versus Apache / php-fpm

* **One process.** ePHPm serves `web/` and runs PHP. `web/.htaccess`
  (`RewriteRule . index.php`) is `[server] fallback` in `ephpm.toml`, and
  the template's pretty-URL `urlManager` block is switched on, so URLs are
  `/site/login` rather than `/index.php?r=site%2Flogin`.
* **Configuration from the environment.** `config/db.php` reads `DB_DSN`,
  `DB_USER`, `DB_PASSWORD`; `web/index.php` and `yii` read `YII_ENV`
  (default `prod`) and `YII_DEBUG` (`1` to enable) instead of the template's
  hard-coded `dev`/`true`; `cookieValidationKey` comes from
  `COOKIE_VALIDATION_KEY`, or is generated once into the `runtime` volume.
* **`yii migrate` runs on start** once the database answers
  (`SKIP_MIGRATE=1` to skip). The template has no migrations of its own; your
  application's are applied the same way.
* **`errorHandler.silentExitOnException = true`** in `config/web.php`. Yii's
  error handler ends with `exit(1)`, which ePHPm v0.11.3 turns into a bare
  500 that throws the rendered error page away (`issues/yii2.md`); with the
  property set, 404/400/500 pages are sent with their real status. Keep it
  in your own app's config until ePHPm fixes this.
* **Template pinned to 2.0.54.** The 2.0.55 release of
  `yiisoft/yii2-app-basic` ships a `models/LoginForm.php` whose class
  docblock is never closed — a `ParseError` on every login, on any server.
  Fixed on the template's master branch; bump `YII_VERSION` once a newer
  release is out.

## Run

```bash
docker compose up -d                # or: podman compose up -d
open http://localhost:8080          # EPHPM_PORT=8090 docker compose up -d to change
```

Log in with `admin` / `admin` or `demo` / `demo` (the template's
hard-coded `app\models\User` identities — replace them in a real app).

```bash
docker compose exec ephpm ephpm php yii migrate                 # console commands
docker compose exec ephpm ephpm php yii migrate/create add_post_table
docker compose exec ephpm ephpm cache reset                     # after changing PHP files
```

For your own application, replace the `composer create-project` line in the
`Dockerfile` with `COPY . /app` + `composer install --no-dev`, and keep
`config/db.php` reading the environment.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | `composer create-project` of the basic template, env-driven `db.php`/`index.php`/`yii`, pretty URLs, `silentExitOnException`, onto `ephpm/ephpm` |
| `demo/db.php` | `config/db.php` reading `DB_DSN` / `DB_USER` / `DB_PASSWORD` |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Generates the cookie key once, waits for the database, `yii migrate`, starts `ephpm serve` |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/yii2/test.sh`) |

## Configuration notes

* `[server.security] blocked_paths` refuses `/config/*`, `/runtime/*`,
  `/vendor/*`, `/models/*`, `/controllers/*`, `/views/*` — they are outside
  the document root anyway; the list guards a misconfigured `document_root`.
* **Cache and sessions in the built-in KV store:** `[kv.redis_compat]`
  listens on `127.0.0.1:6379` inside the container, so
  `yiisoft/yii2-redis` (pure PHP) with `hostname => '127.0.0.1'` can back
  `yii\redis\Cache` and `yii\redis\Session` without a Redis service. Not
  exercised by `test.sh`.
* OPcache runs with timestamp validation off (`ephpm serve` default): run
  `docker compose exec ephpm ephpm cache reset` or restart after changing
  PHP files.

## Known limitations

* **The contact page (`/site/contact`) answers 500**: its CAPTCHA widget
  requires GD with FreeType (or Imagick), and ePHPm's GD has no FreeType
  (same root cause as `issues/monica.md`). Remove the `captcha` action and
  field, or use a non-image CAPTCHA.
* No embedded-database variant: litewire returns an empty set instead of
  error 1146 for `SHOW FULL COLUMNS` on a table that does not exist yet,
  which Yii's schema reader depends on (`issues/yii2.md`); migrations with
  `addForeignKey()` would also hit the known `ADD CONSTRAINT` gap.
