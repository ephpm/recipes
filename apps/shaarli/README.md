# Shaarli on ePHPm

| | |
|---|---|
| App | [Shaarli](https://github.com/shaarli/Shaarli) v0.16.9 (`SHAARLI_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm + s6 (the `shaarli/shaarli` image) |
| Default stack | `compose.yml` — one ePHPm container, no database (Shaarli is flat-file) |
| Single container | that is the default |
| Status | tested 2026-10-11 on v0.11.3-php8.5: web installer, login, bookmark a link through the admin form, read it back on the public page and the Atom feed, session visible in the KV store, private files 403 |

## What changes versus the official image

* **One process.** ePHPm serves the static assets and runs `index.php` (the
  Slim front controller). The nginx `try_files _ /index.php$is_args$args`
  rule becomes `[server] fallback` in `ephpm.toml`; the `data/`, `cache/`,
  `vendor/`… directories that nginx never exposes are listed in
  `[server.security] blocked_paths`, together with the top-level PHP files
  other than `index.php`.
* **Sessions in the KV store.** `session.save_handler = ephpm` keeps PHP
  sessions in ePHPm's in-process store instead of files under `/tmp` — same
  lifetime as before (gone on restart; Shaarli's "stay signed in" cookie
  re-logs you), one fewer directory to manage. Remove the two `session.*`
  lines from `ephpm.toml` to go back to the `files` handler.
* **The release zip, not a Composer step.** `shaarli-<version>-full.zip`
  ships `vendor/` and the built front-end assets, so the image is a
  download + copy. Nothing runs at build time.
* **No environment variables** — Shaarli has none; everything is in
  `data/config.json.php`, written by the web installer.

## Run

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

The first visit shows Shaarli's installer (username, password, title,
timezone). Afterwards log in at `/login`. The `data` volume holds the
configuration, the datastore and the thumbnails cache lives in `cache`; back
up `data`.

### Useful commands

```bash
docker compose exec ephpm ephpm kv keys 'session:*'   # live sessions
docker compose restart ephpm                           # after editing PHP in the container (reloads PHP code)
docker compose logs ephpm                              # PHP errors land here
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the full release zip, trims build-only files, copies it onto `ephpm/ephpm` |
| `ephpm.toml` | Server config: web root, Slim rewrite, blocked private paths, KV sessions |
| `entrypoint.sh` | Creates the writable directories if the volumes were mounted empty, starts `ephpm serve` |
| `compose.yml` | The stack (one service) |
| `test.sh` | The smoke test CI runs (`bash apps/shaarli/test.sh`) |

## Configuration notes

* Uploads/imports: `[server.request] max_body_size` (10 MiB, nginx's
  `client_max_body_size 10m`) and the `upload_max_filesize` /
  `post_max_size` ini overrides move together.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`,
  and Shaarli's own `security.trusted_proxies` in `data/config.json.php`.
* `allowed_php_paths = ["/index.php"]` would be the obvious way to say "only
  the front controller executes", but ePHPm v0.11.3 matches that list against
  the request URI (so `/login` is refused) — see `issues/shaarli.md`. The
  recipe uses `blocked_paths` instead.
* OPcache runs with timestamp validation off (`ephpm serve` default): after
  changing PHP files inside the container run
  `docker compose restart ephpm` (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).
* The REST API (`/api/v1/…`, JWT in the `Authorization` header) routes
  through `index.php` like every other path, but the smoke test does not
  exercise it — untested.

## Known limitations

* `ldap` is not available in the ePHPm build, so Shaarli's optional LDAP
  login (`ldap.*` settings) cannot be used. Form login (the default) is
  unaffected.
* The bundled documentation under `/doc/html/` is served as static files;
  nginx's `try_files $uri $uri/ $uri.html` rule (extensionless doc links)
  has no ePHPm equivalent, so open the `.html` files directly.
* No `favicon.ico` alias: the official nginx config maps `/favicon.ico` to
  a file that the release zip does not ship; browsers get a 404 for it, as
  they do with the official image's default theme.
