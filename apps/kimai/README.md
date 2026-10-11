# Kimai on ePHPm

| | |
|---|---|
| App | [Kimai](https://www.kimai.org) 2.69.0 (`KIMAI_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | `kimai/kimai2:fpm` + nginx, or `kimai/kimai2:apache` |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not available — Kimai supports MySQL/MariaDB only, and Doctrine's MySQL DDL fails on ePHPm's embedded database ([issues/shlink.md](../../issues/shlink.md)) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: `kimai:install` + admin user created by the entrypoint, login through the form, first-login wizard page served, a customer created and read back through the JSON API, `kimai:version` on the console |

## What changes versus the official image

* **One process.** ePHPm serves `public/` and runs PHP; the Symfony rewrite
  from `public/.htaccess` is `[server] fallback` in `ephpm.toml`.
* **Same environment variables as `kimai/kimai2`:** `DATABASE_URL`,
  `APP_SECRET`, `TRUSTED_PROXIES`, `TRUSTED_HOSTS`, `MAILER_FROM`,
  `MAILER_URL`, `ADMINMAIL`, `ADMINPASS`. `entrypoint.sh` does what the
  official entrypoint does: resolves `APP_SECRET` (environment, else a
  generated one persisted in `var/data/.appsecret` and mirrored into
  `.env.local`), waits for the database, runs `kimai:install` (database,
  migrations, cache) on every start, and creates the `admin` user once when
  `ADMINMAIL` + `ADMINPASS` are set.
* **Built from the release tag.** Kimai publishes no dist archive; the
  build stage fetches the `2.69.0` source tarball (its `public/build`
  frontend is already compiled) and runs `composer install --no-dev`, then
  `assets:install` runs on the embedded PHP. `USER_ID`/`GROUP_ID` are not
  used: the container runs as root, as the other recipes do.
* **The console runs on the embedded PHP:**
  `docker compose exec ephpm kimai kimai:user:create ...` (`kimai` wraps
  `ephpm php -d memory_limit=-1 bin/console`, the official image's
  `php-cli.ini` setting).

## Run

```bash
ADMINMAIL=admin@example.com ADMINPASS=change-me docker compose up -d
open http://localhost:8080     # admin / change-me
```

```bash
docker compose exec ephpm kimai kimai:version
docker compose exec ephpm kimai kimai:user:create alice alice@example.com ROLE_USER
docker compose exec ephpm kimai kimai:plugin:install    # after dropping a plugin into var/plugins
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Composer build stage from the release tag, copied onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Seeds `var/`, resolves `APP_SECRET`, waits for the DB, `kimai:install`, admin user, starts `ephpm serve` |
| `kimai` | `bin/console` wrapper over the embedded PHP |
| `compose.yml` | The stack |
| `test.sh` | The smoke test CI runs (`bash apps/kimai/test.sh`) |

## Configuration notes

* `var/` (cache, data incl. `.appsecret`, logs, plugins, sessions) is a
  volume, like the official image's `/opt/kimai/var`.
* Uploads: `[server.request] max_body_size` and the ini overrides are 64 MiB;
  `session.gc_maxlifetime` is 7 days as in the official image.
* Kimai uses its own database-backed session handler
  (`App\Security\SessionHandler`), so the native `ephpm` session handler is
  not involved.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  (ePHPm) and `TRUSTED_PROXIES` (Kimai) to the proxy address.
* OPcache runs with timestamp validation off (ePHPm's `serve` default). After
  installing a plugin run `kimai kimai:reload` **and**
  `ephpm cache reset` (or restart the container).
* Mail: `MAILER_URL=null://localhost` by default; set an SMTP DSN
  (`smtp://user:pass@host:587`) for notifications.
* Cron: Kimai has no mandatory cron jobs.

## Known limitations

* LDAP authentication needs the `ldap` PHP extension, which the ePHPm build
  does not include (the official image adds `laminas/laminas-ldap`). SAML
  works without it.
