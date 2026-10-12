# Open Web Analytics on ePHPm

| | |
|---|---|
| App | [Open Web Analytics](https://www.openwebanalytics.com) 1.14.0 (`OWA_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache/nginx + php-fpm, and the crontab entry for `php cli.php cmd=schedule-run` (there is no official image) |
| Default stack | `compose.yml` — ePHPm + a cron service on the same image + MariaDB 11 |
| Single container | none — not tried against ePHPm's embedded database |
| Status | tested 2026-10-11 on v0.11.3-php8.5: `cli.php cmd=install` on first start (admin password set with `cmd=change-password`), login form, add a tracked site through the admin form, page view sent to `log.php` and stored, tracker script served, `cmd=schedule-status`, restart runs `cmd=update`, `owa-config.php`/code/CLI 403 |

## What changes versus the usual setup

* **One process.** ePHPm serves OWA's application root: `index.php` (admin
  UI and reports), `log.php` (the tracker's event endpoint), `api/` (REST
  API) and the built assets under `public/`. Only those entry points may
  execute (`allowed_php_paths`); `Core/`, `vendor/`, `conf/`, `owa-data/`,
  `owa-config.php` and `cli.php` are refused.
* **Configured from the environment.** On the first start the entrypoint
  writes `owa-config.php` into the `owa-data` volume (the app root has a
  symlink to it): the database settings and `OWA_PUBLIC_URL` are read from
  the environment on every request, the nonce/auth keys and salts are
  generated once per installation.
* **Installed by `cli.php cmd=install`.** That command makes the admin
  password the *database* password; the entrypoint immediately replaces it
  with `OWA_ADMIN_PASSWORD` (`cmd=change-password`). Later starts run
  `cmd=update`.
* **Scheduled jobs** (partition rotation, upstream's
  `* * * * * php cli.php cmd=schedule-run`) run in the `cron` service on the
  same image.
* PHP 8.5 deprecation notices (OWA 1.14 emits hundreds per report page) are
  filtered with `error_reporting = E_ALL & ~E_DEPRECATED`, in `ephpm.toml`
  and in the `owa-cli` wrapper.

## Run

```bash
OWA_ADMIN_PASSWORD=change-me docker compose up -d     # or: podman compose up -d
open http://localhost:8080          # log in as admin
```

`OWA_PUBLIC_URL` (default `http://localhost:${EPHPM_PORT:-8080}/`) must be the
URL OWA is reached at, with the trailing slash: the tracking snippet loads
`public/base/dist/owa.tracker.js` and posts to `log.php` there. First-start
variables: `OWA_ADMIN_USER`, `OWA_ADMIN_PASSWORD`, `OWA_ADMIN_EMAIL`,
`OWA_SITE_DOMAIN` (the first tracked site). Then add sites under
Administration -> Sites & Profiles and copy their tracking code.

```bash
docker compose exec ephpm owa-cli cmd=schedule-status
docker compose exec ephpm owa-cli cmd=change-password user=admin password=new-password
docker compose exec ephpm owa-cli cmd=flush-cache
```

## Known limits

* Reports load their data through the REST API (`api/index.php`); the
  smoke test checks the stored page view in the database rather than in a
  rendered report. A hand-made `GET api/index.php?do=sites` (session cookie,
  no API key) answered 500 with `Call to a member function _getProperties()
  on false` in `owa-data/logs` (`View/SitesRest.php`) — the failure is
  inside OWA's view code; the REST calls the report UI makes were not
  exercised.
* Geolocation (MaxMind) needs a GeoLite2 database file mounted and the
  module enabled, as on any installation.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the packaged release (with `vendor/`), copies it onto `ephpm/ephpm` |
| `ephpm.toml` | Server config: web entry points only, private paths refused |
| `entrypoint.sh` | Writes `owa-config.php`, waits for the DB, installs (or updates), starts `ephpm serve` |
| `owa-cli` | `ephpm php cli.php` with deprecations filtered |
| `compose.yml` | The stack (ePHPm, cron, MariaDB) |
| `test.sh` | The smoke test (`bash apps/open-web-analytics/test.sh`) |
