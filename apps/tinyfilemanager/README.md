# Tiny File Manager on ePHPm

| | |
|---|---|
| App | [Tiny File Manager](https://tinyfilemanager.github.io) 2.6 (`TFM_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `tinyfilemanager/tinyfilemanager` image (`php -S`, PHP's development server, on PHP 7.4) |
| Default stack | `compose.yml` — ePHPm only (no database) |
| Single container | yes — it is one already |
| Status | tested 2026-10-11 on v0.11.3-php8.5: login form with CSRF token, create a folder, upload a file (Dropzone chunk POST), list and download it back, file present on the `/data` volume, `config.php` 403, managed files not served directly |

## What changes versus the upstream image

* **A real HTTP server instead of `php -S`.** The upstream image runs PHP's
  single-threaded built-in development server; ePHPm serves concurrent
  requests and current PHP (8.5 instead of 7.4).
* **Managed files are outside the web root.** The upstream image manages
  `/var/www/html` — the directory it serves from, next to the app itself, so
  an uploaded `.php` file is executable at its URL. Here the app is the only
  thing in `/app` (the document root) and `$root_path` is `/data`, a volume;
  files are reached only through the app (`?p=…&dl=…`), never by URL, and
  `[server] fallback` ends in `=404`. The trade-off: the "direct link" in the
  file view does not resolve (upstream: "will not work if `$root_path` is
  outside the document root").
* **Configured from the environment.** The app reads an optional
  `config.php` next to itself (upstream's documented override). The
  entrypoint writes it on every start from the variables below, hashing the
  passwords with `password_hash()`. The built-in `admin/admin@123` and
  `user/12345` accounts are gone; with no password set, one is generated and
  printed in the log.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `TFM_ADMIN_USER` | `admin` | the read/write account |
| `TFM_ADMIN_PASSWORD` / `TFM_ADMIN_PASSWORD_HASH` | generated | its password, plain or as a `password_hash()` string |
| `TFM_READONLY_USER` + `TFM_READONLY_PASSWORD` / `_HASH` | — | an optional read-only account |
| `TFM_ROOT_PATH` | `/data` | the directory being managed |
| `TFM_ALLOWED_UPLOAD_EXTENSIONS` | (any) | e.g. `jpg,png,pdf,txt` |
| `TFM_ONLINE_VIEWER` | `false` | `google` / `microsoft` sends document URLs to that viewer; off by default (and the URLs would not resolve, see above) |
| `TFM_MAX_UPLOAD_SIZE_BYTES` | `5000000000` | per-file limit (uploads arrive in 2 MB chunks) |
| `TZ` | `Etc/UTC` | timezone for file dates |

Anything else in upstream's `config-sample.txt` (IP allow/deny lists,
`$exclude_items`, per-user directories, …) can be added by baking your own
`config.php` into the image instead of the generated one.

## Run

```bash
TFM_ADMIN_PASSWORD='something-long' docker compose up -d   # or: podman compose up -d
open http://localhost:8080        # EPHPM_PORT=8090 ... to change
```

To manage a host directory instead of the `data` volume, replace the volume
line with a bind mount (`- /srv/share:/data`).

```bash
docker compose exec ephpm ls -la /data
docker compose exec ephpm ephpm php -r 'echo password_hash("secret", PASSWORD_DEFAULT), "\n";'   # make a _HASH value
docker compose logs ephpm
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | `tinyfilemanager.php` → `/app/index.php` on `ephpm/ephpm` |
| `ephpm.toml` | Server config (`/app` root, `=404` fallback, 16 MiB request bodies) |
| `entrypoint.sh` | Writes `config.php` from the environment, starts `ephpm serve` |
| `compose.yml` | The single service + the `data` volume |
| `test.sh` | The smoke test CI runs (`bash apps/tinyfilemanager/test.sh`) |

## Configuration notes

* The app loads Bootstrap, jQuery, Ace, highlight.js and Dropzone from public
  CDNs (jsdelivr, cdnjs, code.jquery.com), as upstream; the browser needs
  internet access.
* Uploads are chunked by the browser (2 MB), so `max_body_size` stays at
  16 MiB; large files work regardless of their size.
* Zipping/unzipping uses PHP's `zip` and `phar`, both built in.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`.

## Known limitations

* Direct file links (and the Google/Microsoft online viewers) do not work,
  by design of this recipe: the managed files are not under the web root.
* The app runs as root inside the container, so it can write anything in
  `/data`; mount only what it should manage.
