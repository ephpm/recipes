# DokuWiki on ePHPm

| | |
|---|---|
| App | [DokuWiki](https://www.dokuwiki.org) 2026-07-14c "Mort" (`DOKUWIKI_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache/nginx + php-fpm (DokuWiki has no official image; this replaces the community ones) |
| Default stack | `compose.yml` — one ePHPm container, no database (DokuWiki is flat-file) |
| Single container | that is the default |
| Status | tested 2026-10-11 on v0.11.3-php8.5: web installer, superuser login, create a page through the editor and read it back (file in the `data` volume), session in the KV store, private directories 403 |

## What changes versus a stock Apache/nginx install

* **One process.** ePHPm serves `doku.php`, `lib/exe/*.php` and the static
  assets. The directories DokuWiki ships a "deny all" `.htaccess` for
  (`bin/ conf/ data/ inc/ vendor/`) and the files its `.htaccess.dist` hides
  are refused with `[server.security] blocked_paths`.
* **Stock URLs only** (`userewrite = 0`, DokuWiki's default). The "nice
  URL" modes need regex rewrites (`userewrite = 1`) or `PATH_INFO`
  (`userewrite = 2`); ePHPm provides neither, so leave the setting at 0.
* **Sessions in the KV store.** `session.save_handler = ephpm` keeps PHP
  sessions in ePHPm's in-process store instead of files under `/tmp`
  (DokuWiki's "remember me" cookie survives a restart; the session itself
  does not).
* **Four volumes** hold everything DokuWiki writes: `data` (pages, media,
  attic, cache, index), `conf` (configuration, users, ACL), `lib/plugins`
  and `lib/tpl` (installed from the Extension Manager). They are seeded
  from the image on first start.

## Run

```bash
docker compose up -d                   # or: podman compose up -d
open http://localhost:8080/install.php # EPHPM_PORT=8090 docker compose up -d to change
```

Complete the installer (wiki name, superuser, ACL policy). The installer
refuses to run again once `conf/local.php` exists; it tells you to delete
`install.php`, which in this image means rebuilding — or just add
`"/install.php"` to `blocked_paths` in `ephpm.toml`.

```bash
docker compose exec ephpm php bin/indexer.php -c        # rebuild the search index
docker compose exec ephpm php bin/plugin.php list       # installed plugins
docker compose restart ephpm                            # after installing plugins/templates (reloads PHP code)
docker compose exec ephpm ephpm kv keys 'session:*'     # live sessions
```

(`php` is not on PATH in the ePHPm image; use `ephpm php bin/…`.)

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release tarball (vendor included), copies it onto `ephpm/ephpm`, keeps pristine copies to seed the volumes |
| `ephpm.toml` | Server config: web root, blocked private paths, 32 MiB uploads, KV sessions |
| `entrypoint.sh` | Seeds empty volumes, creates the `data/*` directories, starts `ephpm serve` |
| `compose.yml` | The stack (one service, four volumes) |
| `test.sh` | The smoke test CI runs (`bash apps/dokuwiki/test.sh`) |

## Configuration notes

* Media uploads: `[server.request] max_body_size` (32 MiB) and the
  `upload_max_filesize` / `post_max_size` ini overrides move together.
* Behind a TLS-terminating proxy set `[server.security] trusted_proxies`;
  DokuWiki's `baseurl` config option covers a different public URL.
* OPcache runs with timestamp validation off (`ephpm serve` default): run
  `docker compose restart ephpm` after installing or updating plugins and templates from the
  Extension Manager (`ephpm cache reset` is a no-op on a single node in v0.11.3, `issues/nextcloud.md`).
* The daily cleanup DokuWiki's docs suggest (`bin/cleanup.sh`, cache and
  attic pruning) is not scheduled; run `php bin/…` from a host cron if you
  need it.

## Known limitations

* No nice URLs (see above).
* `imagick` is not available; DokuWiki resizes images with GD, which is
  compiled in.
