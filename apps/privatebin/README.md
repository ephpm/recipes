# PrivateBin on ePHPm

| | |
|---|---|
| App | [PrivateBin](https://privatebin.info) 2.0.6 (`PRIVATEBIN_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm + s6 (the `privatebin/nginx-fpm-alpine` image) |
| Default stack | `compose.yml` — one ePHPm container, pastes as files (PrivateBin's default) |
| Single container | that is the default |
| Status | tested 2026-10-11 on v0.11.3-php8.5: home page, create a paste through the JSON API, read it back (ciphertext intact, file under /srv/data), delete it with its token, config not reachable from the web root |

## What changes versus the official image

* **One process.** ePHPm serves `index.php` and the static assets; the
  nginx `try_files $uri $uri/ /index.php$is_args$args` rule is `[server]
  fallback` in `ephpm.toml`, and the hardening headers nginx adds
  (`X-Frame-Options`, `Referrer-Policy`, `Cross-Origin-*`, `nosniff`) are
  `[server.response] headers`.
* **Same layout as the official image.** `bin/ cfg/ lib/ tpl/ vendor/` live
  under `/srv`, outside the web root, and `index.php`'s `PATH` points there;
  pastes, the server salt and the traffic limiter are in `/srv/data` (the
  `data` volume). A custom `conf.php` is mounted at `/srv/cfg/conf.php`,
  exactly as with the official image.
* **No environment variables** — PrivateBin has none beyond `CONFIG_PATH`
  (an alternative directory for `conf.php`, honoured here too).

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

Nothing to install. To change options (file uploads, expiry, template, a
database backend) copy `conf.php`, edit it, and mount it:

```yaml
    volumes:
      - data:/srv/data
      - ./conf.php:/srv/cfg/conf.php:ro
```

The bundled `conf.php` is PrivateBin's sample config reduced to the keys
the recipe sets (`sizelimit`, `template`, `traffic.limit`, the expiry
options, the `Filesystem` model); the full option list is in PrivateBin's
`cfg/conf.sample.php`.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release (vendor is committed), moves code/config under `/srv`, copies onto `ephpm/ephpm` |
| `conf.php` | Default PrivateBin configuration (`/srv/cfg/conf.php`) |
| `ephpm.toml` | Server config: web root, rewrite, headers, body limit |
| `entrypoint.sh` | Creates `/srv/data` if the volume was mounted empty, starts `ephpm serve` |
| `compose.yml` | The stack (one service) |
| `test.sh` | The smoke test CI runs (`bash apps/privatebin/test.sh`) |

## Configuration notes

* Paste size: `[server.request] max_body_size` (10 MiB) and the
  `post_max_size` / `upload_max_filesize` ini overrides match `[main]
  sizelimit` in `conf.php`; raise all of them together.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`
  (PrivateBin's traffic limiter keys on the client IP) and `[main]
  basepath` in `conf.php` when the public URL differs.
* A database backend (`[model] class = Database` with MySQL/PostgreSQL via
  PDO) works as documented by PrivateBin — `pdo_mysql` / `pdo_pgsql` are
  compiled into ePHPm. The S3 and Google Cloud Storage backends need their
  SDKs (`composer require`), which this image does not bundle.
* OPcache runs with timestamp validation off (`ephpm serve` default); after
  editing PHP in the container run `docker compose exec ephpm ephpm cache
  reset` or restart. Editing `conf.php` needs no restart beyond PrivateBin's
  own config caching (none).

## Known limitations

* `--read-only` container mode as advertised by the official image is not
  tested here; ePHPm needs `/run` and `/tmp` writable.
