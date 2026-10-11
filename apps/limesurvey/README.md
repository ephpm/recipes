# LimeSurvey on ePHPm

| | |
|---|---|
| App | [LimeSurvey](https://www.limesurvey.org) 7.5.0 (`LIMESURVEY_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the widely used `martialblog/limesurvey` image) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | none — not attempted |
| Status | tested 2026-10-11 on v0.11.3-php8.5: `console.php install` on first start, admin login (path-format URLs), create a survey and read it back in the survey list and through the REST API (`/rest/v1/...`, bearer token), the new editor's static app, private paths 403, `console.php` on the embedded PHP. Error pages are a bare 500 (see Known limitations) |

## What changes versus the `martialblog/limesurvey` image

* **One process.** ePHPm serves the tree; LimeSurvey's `.htaccess`
  front-controller rule is `[server] fallback`, and the paths its
  `.htaccess` files deny (`application/`, `vendor/`, `locale/`,
  `tmp/runtime/`, `docs/`, the dev/meta files) are
  `[server.security] blocked_paths`.
* **Path-format URLs without `PATH_INFO`.** LimeSurvey 7 needs
  `urlFormat = path` (`/index.php/admin/...`, `/rest/v1/...`) for its REST
  API and new editor. ePHPm has no `PATH_INFO`, but Yii derives the route
  from `REQUEST_URI`, so both `/index.php/...` and `/rest/...` work.
* **Same variable names.** `DB_TYPE` (`mysql` | `pgsql`), `DB_HOST`,
  `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD` (or `_FILE`),
  `DB_TABLE_PREFIX`, `DB_CHARSET`, `DB_MYSQL_ENGINE` (default `InnoDB`
  here, `MyISAM` in that image), `ADMIN_USER`, `ADMIN_NAME`, `ADMIN_EMAIL`,
  `ADMIN_PASSWORD` (or `_FILE`), `PUBLIC_URL`, `URL_FORMAT`,
  `SHOW_SCRIPT_NAME`, `DEBUG`, `DEBUG_SQL`, and the `ENCRYPT_*` keys.
  `config.php` reads them at runtime instead of being generated once, so
  changing a variable takes effect on restart.
* **Install / upgrade on start** as in that image: `console.php updatedb`,
  and `console.php install` when the database is empty.
* **Encryption keys persist.** `application/config/security.php` (generated
  by LimeSurvey on first use, or from `ENCRYPT_*`) is a link into the
  `config` volume; uploads (`upload/`) are the other volume.
* **OPcache checks timestamps** (`opcache_validate_timestamps = true`, every
  2 s): ComfortUpdate and the plugin manager replace PHP files from the UI.

## Run

```bash
docker compose up -d                # or: podman compose up -d
open http://localhost:8080/admin    # EPHPM_PORT=8090 ... to change
```

Log in with `ADMIN_USER` / `ADMIN_PASSWORD` (`admin` /
`LimeSurvey-Admin-Pass-1` — set your own, and `DB_PASSWORD`, in a `.env`
file before the first start).

```bash
docker compose exec ephpm php application/commands/console.php updatedb
docker compose exec ephpm php application/commands/console.php resetpassword admin 'New-Pass-1'
```

`php` in the image is a shim for `ephpm php` (and `PHP_BINARY` points at it,
for tools that re-invoke PHP — see `issues/pterodactyl.md`).

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | The release tag (vendor and built assets committed upstream) onto `ephpm/ephpm` |
| `config.php` | `application/config/config.php`, read from the environment |
| `ephpm.toml` | Server config: front-controller fallback, `.htaccess` denials, 100 MiB uploads, OPcache timestamp checks |
| `entrypoint.sh` | Seeds `upload/`, `ENCRYPT_*` → `security.php`, waits for the DB, `updatedb` or `install`, `ephpm serve` |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/limesurvey/test.sh`) |

## Configuration notes

* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  and, if generated links come out wrong, `PUBLIC_URL`.
* Email: configure SMTP in Global settings → Email settings.

## Known limitations

* **Error pages are ePHPm's bare 500.** LimeSurvey (Yii 1) renders its
  404/403/error page from the exception handler and then calls `exit()`;
  ePHPm v0.11.3 treats an `exit()` there as a Zend bailout, answers 500 and
  discards the page ([`issues/limesurvey.md`](../../issues/limesurvey.md)).
  Unknown URLs and permission errors therefore show
  `PHP execution error: PHP script bailed out` instead of LimeSurvey's
  message. Normal pages, the admin and the REST API are unaffected (taking
  a survey as a respondent was not exercised by the smoke test).
* ePHPm has no per-prefix routing: `.htaccess` exempts `/editor/` from the
  front controller, here unknown `/editor/...` paths go to `index.php`
  (the editor itself, a hash-routed app under `/editor/`, works).
* GD in ePHPm has no JPEG/WebP/FreeType: image questions/uploads in JPEG are
  stored but not resized, and statistics charts that need TrueType text do
  not render.
