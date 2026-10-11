# Grav on ePHPm

| | |
|---|---|
| App | [Grav](https://getgrav.org) 2.2.6, the `grav-admin` package (admin2 panel + API plugin) (`GRAV_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache/nginx + php-fpm (the `linuxserver/grav` image) |
| Default stack | `compose.yml` — one container; Grav is flat-file, no database |
| Single container | that is the default |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, admin account created with Grav's CLI on start, home page and a page route, admin panel and its assets, login through the API plugin (`/api/v1/auth/token`), a page created through the API and served at its route, private paths (accounts, config, page Markdown, cache) refused, `bin/grav clearcache` |

## What changes versus nginx + php-fpm

* **One process.** ePHPm serves the files and runs PHP; the
  `try_files $uri $uri/ /index.php?$query_string` rule is `[server] fallback`.
* **The security block of Grav's `nginx.conf`** becomes `[server.security]
  blocked_paths`. ePHPm's patterns match whole path segments (`*` is one
  segment), so the translation is not one-to-one:
  * stricter than nginx: all of `user/accounts/` and `user/data/` is
    refused (nginx lets images there through — account avatars and Flex
    object media), and all of `vendor/`;
  * looser than nginx: the "any file with this extension anywhere under
    `user/`/`system/`" rules are spelled out per depth — page Markdown up to
    six folders deep, plugin PHP up to four, theme PHP/YAML/templates — so
    a `.yaml`/`.twig`/`.txt` file nested deeper in a plugin or theme is
    served. None of those hold secrets in a stock install; secrets
    (`user/config`, `user/accounts`, `user/env`) are refused whole.
  Dotfiles are refused by ePHPm's `hidden_files` default.
* **`user/` is the volume** (config, pages, accounts, plugins, themes),
  seeded from the image when empty; `backup/` is a second volume. `cache/`,
  `logs/`, `images/`, `assets/` and `tmp/` are regenerated and live in the
  container.
* **First admin account**: set `GRAV_ADMIN_USER` / `GRAV_ADMIN_PASSWORD`
  (and `GRAV_ADMIN_EMAIL`) and the entrypoint creates it with `bin/plugin
  login new-user` on start; otherwise the admin panel asks for one on the
  first visit. The password must satisfy Grav's password policy, or the
  container exits with Grav's message.

## Run

```bash
docker compose up -d                # or: podman compose up -d
open http://localhost:8080          # EPHPM_PORT=8090 docker compose up -d to change
open http://localhost:8080/admin
```

Grav's CLI runs on the embedded PHP:

```bash
docker compose exec ephpm ephpm php bin/grav clearcache
docker compose exec ephpm ephpm php bin/gpm install <plugin>     # plugins/themes go to the user/ volume
docker compose exec ephpm ephpm php bin/grav backup
docker compose exec ephpm ephpm php bin/plugin login new-user
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the `grav-admin` release (vendor included), onto `ephpm/ephpm`; `php` wrapper |
| `ephpm.toml` | Server config (routing, the nginx security block as `blocked_paths`) |
| `entrypoint.sh` | Seeds `user/`, optionally creates the first admin, starts `ephpm serve` |
| `compose.yml` | The single-container stack |
| `test.sh` | The smoke test CI runs (`bash apps/grav/test.sh`) |

## Configuration notes

* Grav caches compiled pages and Twig templates itself (`cache/`); after
  editing pages or config by hand run `bin/grav clearcache`. PHP code
  changes (plugins, themes) need a container restart: OPcache timestamp
  validation is off under `ephpm serve`, and `ephpm cache reset` is a no-op
  on a single node in v0.11.3 (`issues/nextcloud.md`).
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`.

## Known limitations

* **Image processing**: ePHPm's GD has no JPEG/WebP/AVIF support
  (`issues/koel.md`), so Grav's image derivatives (`?cropResize=…`,
  `srcset` sizes) work for PNG/GIF only. Plain JPEG media are served as
  uploaded. Not exercised by `test.sh`.
* `bin/gpm selfupgrade` replaces Grav's core inside the container, which is
  lost on the next image rebuild — upgrade by bumping `GRAV_VERSION`
  instead.
