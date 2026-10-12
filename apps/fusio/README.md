# Fusio on ePHPm

| | |
|---|---|
| App | [Fusio](https://www.fusio-project.org) 7.2.0 (`fusio/impl` 8.8.9; `FUSIO_VERSION` build arg) with the backend 7.2.0, developer 7.2.1, account 2.4.0 and redoc 1.0.4 web apps |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the official `fusio/fusio` image: Apache + mod_php + cron + supervisord (Messenger worker) |
| Default stack | `compose.yml` — ePHPm + `cron` and `worker` sidecars (same image) + MariaDB 11 |
| Single container | none — not attempted: Fusio's schema is built with Doctrine DBAL/Migrations' MySQL platform, whose DDL the embedded database rejects (see `issues/shlink.md`) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: migrations + backend user on first start, API root and backend app (API URL written by `marketplace:env`), OAuth2 token for the backend user, create an action and a public operation through the backend API and call the new endpoint, the cron sidecar executes a Fusio cronjob, `bin/fusio` on the embedded PHP |

## What changes versus the official image

* **One web process.** ePHPm serves `public/`; `public/.htaccess`'s
  "everything that is not a file → `index.php`" is `[server] fallback`
  (Fusio routes on `REQUEST_URI`, so the `index.php/$1` `PATH_INFO` form is
  not needed). The bundled web apps are static files under `/apps/`.
* **Same variables.** `FUSIO_PROJECT_KEY`, `FUSIO_CONNECTION`, `FUSIO_URL`,
  `FUSIO_APPS_URL`, `FUSIO_ENV`, `FUSIO_DEBUG`, `FUSIO_MAILER`,
  `FUSIO_MESSENGER`, `FUSIO_MAIL_SENDER`, `FUSIO_TRUSTED_IP_HEADER`,
  `FUSIO_TENANT_ID`, `FUSIO_BACKEND_USER` / `_EMAIL` / `_PW` — the release's
  `configuration.php` is switched to these names at build time, as the
  official image ships it, and logs go to the container log.
* **Same start-up steps** (`entrypoint.sh`): `system:wait_for`,
  `migration:migrate` when not up to date, `adduser --role=1` when there is
  no user, `marketplace:env` (writes `FUSIO_URL`/`FUSIO_APPS_URL` into the
  apps), `login` + `deploy` (`.fusio.yml`) + `logout`.
* **Sidecars instead of cron + supervisord.** `cron` runs
  `bin/fusio system:cronjob` every minute (Fusio's own cronjobs) and
  `system:log_rotate` / `system:clean` once a month; `worker` runs
  `bin/fusio messenger:consume --time-limit=3600` (restarted by compose when
  it exits). The official image's `FUSIO_WORKER_*` connections (Java/JS/PHP/
  Python action workers) are not wired up; create the Worker connections in
  the backend if you run those containers.

## Run

```bash
docker compose up -d                      # or: podman compose up -d
open http://localhost:8080/apps/fusio/    # backend: admin / Fusio-Admin-Pass-1
```

Set `FUSIO_PROJECT_KEY` (32 random hex characters — it encrypts stored
connection credentials, so never change it afterwards), `FUSIO_BACKEND_PW`,
`DB_PASSWORD` and `DB_ROOT_PASSWORD` in a `.env` file before the first
start. `FUSIO_URL` must be the public URL of the API (`EPHPM_PORT=8090` →
`FUSIO_URL=http://localhost:8090`, `FUSIO_APPS_URL=http://localhost:8090/apps`).

```bash
docker compose exec ephpm ephpm php bin/fusio system:check user
docker compose exec ephpm ephpm php bin/fusio adduser --role=1 --username=me --email=me@example.com --password=...
```

## Known limitations

* The apps are part of the image (no volume): apps installed from the
  marketplace in the backend are lost when the container is recreated — add
  them to the Dockerfile instead.
* Apache excludes `/apps/` from the rewrite (a missing file there is a
  plain 404); ePHPm's single fallback chain sends it to `index.php`, which
  answers with Fusio's JSON 404 instead.
* Not exercised: mail (`FUSIO_MAILER`), the marketplace, the SDK generator
  (needs `SDKGEN_CLIENT_ID`/`_SECRET`).
