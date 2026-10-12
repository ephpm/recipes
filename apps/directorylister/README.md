# Directory Lister on ePHPm

| | |
|---|---|
| App | [Directory Lister](https://www.directorylister.com) 5.7.0 (`DL_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | a web server (Apache/nginx) + php-fpm in front of the release (there is no official image) |
| Default stack | `compose.yml` — one ePHPm container, the listed files in a volume on `/data` |
| Single container | it is one container: Directory Lister has no database |
| Status | tested 2026-10-11 on v0.11.3-php8.5: listing, files added to the data volume show up, download through `?file=`, sub-directory listing with its README rendered, search, file-info hashes, directory zip download, `../` traversal refused, built assets served, code paths 403 |

## What changes versus the usual setup

* **One process.** ePHPm serves `index.php` and the built assets under
  `app/assets` / `app/images`; nothing else in the release is reachable.
  `index.php` is the only PHP file allowed to run
  (`[server.security] allowed_php_paths`), and `app/config`, `app/src`,
  `app/vendor`, `app/views`, `app/translations` and `app/cache` are refused
  with `blocked_paths`.
* **The listed files are not the web root.** The release's default is to
  list its own directory and let the web server serve the files directly.
  Here `FILES_PATH=/data`: the application stays in the image, the files sit
  in a volume, and every download goes through Directory Lister's `?file=`
  handler (which honours hidden-file rules and refuses `../`). `index.php`
  restricts PHP's `open_basedir` to the application and `FILES_PATH`.
* **Configuration is environment variables**, as documented upstream
  (https://docs.directorylister.com/configuration): `SITE_TITLE`,
  `APP_LANGUAGE`, `DISPLAY_READMES`, `READMES_FIRST`, `ZIP_DOWNLOADS`,
  `ZIP_COMPRESS`, `SORT_ORDER`, `REVERSE_SORT`, `HIDDEN_FILES_LIST`,
  `HIDE_DOT_FILES`, `DATE_FORMAT`, `TIMEZONE`, `MAX_HASH_SIZE`, ... Set them
  under `environment:` in `compose.yml`.

## Run

```bash
docker compose up -d                # or: podman compose up -d
docker compose cp ./some-file ephpm:/data/
open http://localhost:8080          # EPHPM_PORT=8090 ... to change
```

To list a directory on the host instead of the volume, replace the `files`
volume with a bind mount (`- /srv/public-files:/data:ro`).

`ephpm php` runs Directory Lister's PHP if you need it:

```bash
docker compose exec ephpm ephpm php -r 'require "app/vendor/autoload.php"; echo "ok\n";'
```

## Known limits

* `CACHE_DRIVER=redis` / `memcached` need the `redis` / `memcached` PHP
  extensions, which ePHPm's PHP build does not have; keep the default
  `file` cache (`app/cache` inside the container — it is disposable).
  `apcu` is not available either.
* `DIRECT_LINKS` has no effect with `FILES_PATH` set (upstream behaviour),
  so every file is served through PHP. For very large files that is a
  streaming response from PHP rather than a static file from the web server.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release (vendor and built assets included), copies it onto `ephpm/ephpm` with `FILES_PATH=/data` |
| `ephpm.toml` | Server config: only `index.php` executes, the code directories are refused |
| `compose.yml` | The stack |
| `test.sh` | The smoke test (`bash apps/directorylister/test.sh`) |
