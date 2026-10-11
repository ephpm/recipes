# RSS-Bridge on ePHPm

| | |
|---|---|
| App | [RSS-Bridge](https://github.com/RSS-Bridge/rss-bridge) release `2025-08-05` (`RSSBRIDGE_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `rssbridge/rss-bridge` image (nginx + php-fpm) |
| Default stack | `compose.yml` — one container, no database (file cache) |
| Single container | that is the default |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (`compose.yml`): image build, bridge list, `detect` action, DemoBridge feeds in Atom and JSON, file cache written, a custom bridge from the `/config` volume picked up after a restart, code/config/cache paths refused. Also checked by hand: `CssSelectorBridge` against a live site (outbound HTTPS from the container), and the CLI mode line below |

## What changes versus the official image

* **One process.** ePHPm serves the files and runs PHP. Everything goes
  through `index.php?action=…`; there is no rewrite rule to translate.
* **`/config` works as in the official image:** `*Bridge.php`,
  `*Format.php`, `config.ini.php`, `whitelist.txt` and `DEBUG` placed
  there are copied into the application on start.
* **Settings from the environment:** RSS-Bridge itself reads
  `RSSBRIDGE_<section>_<key>` variables (`RSSBRIDGE_system_enabled_bridges`,
  `RSSBRIDGE_cache_type`, …), so they work unchanged.
* **Code, cache and config are refused** (`[server.security]
  blocked_paths`): the official nginx config denies only dotfiles,
  `vendor/` and `tests/`; here the file cache, `config*.ini.php`,
  `whitelist.txt` and the code directories are refused too — only
  `index.php` and `static/` are meant to be fetched.
* **Release, not master:** the image builds the latest tagged release.
  The official `latest` image builds the master branch; set
  `RSSBRIDGE_VERSION` to a commit hash (or `refs/heads/master`) to follow it.

## Run

```bash
docker compose up -d                # or: podman compose up -d
open http://localhost:8080          # EPHPM_PORT=8090 docker compose up -d to change
```

```bash
# a custom bridge
docker compose cp MyBridge.php ephpm:/config/MyBridge.php && docker compose restart ephpm
# the CLI mode (index.php reads its parameters from argv)
docker compose exec ephpm ephpm php index.php action=display bridge=DemoBridge context=testCheckbox format=Atom
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release source, onto `ephpm/ephpm` |
| `ephpm.toml` | Server config |
| `entrypoint.sh` | Copies custom files from `/config` (as the official entrypoint does), starts `ephpm serve` |
| `compose.yml` | The single-container stack |
| `test.sh`, `test/RecipeBridge.php` | The smoke test CI runs (`bash apps/rss-bridge/test.sh`) and its custom bridge |

## Configuration notes

* The request timeout is 60 s (`[server.timeouts] request`) and
  `max_execution_time` 45 s, matching the official nginx
  `fastcgi_read_timeout`.
* Restart the container after changing bridges by hand inside it (OPcache
  timestamp validation is off under `ephpm serve`; `ephpm cache reset` is a
  no-op on a single node in v0.11.3, `issues/nextcloud.md`). Files dropped
  into `/config` are copied on restart anyway.

## Known limitations

* Bridges that resolve DNS with `dns_get_record()`/`checkdnsrr()` would
  hang on ePHPm v0.11.3 (`issues/freshrss.md`); no code in this release
  calls them (checked with grep) — bridges fetch with curl. Keep it in mind
  for custom bridges.
