# FileGator on ePHPm

| | |
|---|---|
| App | [FileGator](https://filegator.io) 7.16.5 (`FILEGATOR_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the official `filegator/filegator` image) |
| Default stack | `compose.yml` — one ePHPm container; files in the `repository` volume, users/sessions/logs in the `private` volume |
| Single container | it is one container: FileGator has no database (users are in `private/users.json`) |
| Status | tested 2026-10-11 on v0.11.3-php8.5: frontend loads, bad CSRF token refused, wrong password refused, login through the JSON API, create a folder, chunked upload, listing, download, rename, edit in place, logout, nothing above `dist/` served. **Zip / Unzip do not work** on this image (`ZipArchive` cannot deflate, see `issues/filegator.md`) |

## What changes versus the official image

* **One process.** ePHPm serves `dist/` — the official image's Apache
  `DocumentRoot` — which holds the single front controller (`index.php`,
  every API call is `/?r=/<route>`) and the built Vue frontend. The code,
  `configuration.php`, `private/` and `repository/` sit above it and are never
  reachable. Only `index.php` may execute (`allowed_php_paths`).
* **Same volumes:** `/var/www/filegator/repository` (the managed files) and
  `/var/www/filegator/private` (users, sessions, logs, temp files).
* **A per-installation CSRF key.** The upstream sample configuration ships
  `csrf_key => "123456"`; here the key is `FILEGATOR_CSRF_KEY` or one
  generated into `private/csrf_key` on first start.
* **Sessions in `private/sessions`** (the volume) rather than the system temp
  directory, so a restart does not log everyone out. FileGator forces
  Symfony's file session handler, so ePHPm's KV session handler is not used.
* **Admin password from the environment.** When `private/users.json` is first
  created from the blank template, `FILEGATOR_ADMIN_PASSWORD` (if set) becomes
  the `admin` password; otherwise it is upstream's `admin123` — change it.
* The application log also goes to the container log (stderr).

The rest of `configuration.php` is upstream's sample. To use LDAP,
WordPress or database authentication, or S3/SFTP storage, mount your own
file over `/var/www/filegator/configuration.php` (the S3/SFTP adapters also
need the extra Composer packages the official image adds).

## Run

```bash
FILEGATOR_ADMIN_PASSWORD=change-me docker compose up -d     # or: podman compose up -d
open http://localhost:8080          # EPHPM_PORT=8090 ... to change
```

Environment: `FILEGATOR_ADMIN_PASSWORD`, `FILEGATOR_CSRF_KEY`,
`FILEGATOR_APP_NAME`, `FILEGATOR_TIMEZONE`.

PHP from the CLI, e.g. to reset the admin password:

```bash
docker compose exec ephpm ephpm php -r '
  $f = "private/users.json"; $u = json_decode(file_get_contents($f), true);
  foreach ($u as &$x) if ($x["username"] === "admin") $x["password"] = password_hash("new-pass", PASSWORD_BCRYPT);
  file_put_contents($f, json_encode($u));'
```

## Known limits

* **Zip and Unzip fail** (HTTP 500, `ZipArchive::close(): Zlib error: stream
  error` in the log): ePHPm v0.11.3's `ZipArchive` cannot write or read
  deflated entries (`issues/filegator.md`). Uploading, downloading single
  files, moving, renaming and editing work; "download selection as zip"
  (`batchdownload`) uses the same archiver and fails too.
* Uploads are chunked by the frontend (1 MiB chunks, 100 MiB per file by
  default — `frontend_config.upload_max_size`); `[server.request]
  max_body_size` is 100 MiB.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release build (vendor + built frontend) and copies it onto `ephpm/ephpm` |
| `configuration.php` | Upstream's sample with the CSRF key, sessions, app name/timezone and logging changes marked "ePHPm recipe" |
| `ephpm.toml` | Server config: document root `dist/`, only `index.php` executes |
| `entrypoint.sh` | Seeds `private/`, generates the CSRF key, applies `FILEGATOR_ADMIN_PASSWORD`, starts `ephpm serve` |
| `compose.yml` | The stack |
| `test.sh` | The smoke test (`bash apps/filegator/test.sh`) |
