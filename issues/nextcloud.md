# ePHPm issues found while writing the Nextcloud recipe

Found on `ephpm/ephpm:v0.11.3-php8.5` (PHP 8.5.7), 2026-10-11, with
Nextcloud 35.0.1.

## 1. `ephpm cache reset` does nothing on a single node (unless `[opcache] cluster_invalidation = true`)

**Severity: high (operations; every recipe README tells users to run it).**
`ephpm serve` runs with `opcache.validate_timestamps=0`, and the startup log
says "code changes require `ephpm deploy` or `ephpm cache reset`". Both
commands write `opcache:version:<vhost>` through the RESP listener and print
`cache reset: vhost=_DEFAULT at …`, but the server only *reads* that key when
the OPcache watcher is on — and `OpcacheConfig::effective_cluster_invalidation`
defaults it to `[cluster] enabled`, i.e. **off** on a single node. The reset
is silently ignored; the old bytecode keeps being served until a restart.

### Minimal repro (stock image)

```bash
for cfg in "" '[opcache]\ncluster_invalidation=true\n'; do
  podman run --rm --entrypoint sh docker.io/ephpm/ephpm:v0.11.3-php8.5 -c '
    mkdir -p /w && echo "<?php echo 1;" > /w/t.php
    printf "[server]\nlisten=\"127.0.0.1:8080\"\ndocument_root=\"/w\"\n[kv.redis_compat]\nenabled=true\nlisten=\"127.0.0.1:6379\"\n'"$cfg"'" > /a.toml
    (ephpm serve --config /a.toml > /a.log 2>&1 &); sleep 2
    g(){ ephpm php -r "echo file_get_contents(\"http://127.0.0.1:8080/t.php\");"; }
    g; g; echo "<?php echo 2;" > /w/t.php; ephpm cache reset >/dev/null; sleep 1; g; g; echo'
done
# 1111   <- default config: still the old script after `cache reset`
# 1122   <- with [opcache] cluster_invalidation = true
```

### Cause

`crates/ephpm-server/src/router.rs` (Router construction, `opcache_watcher:`)
builds `OpcacheWatcher::new(config.opcache.effective_cluster_invalidation(config.cluster.enabled))`;
`crates/ephpm-config/src/lib.rs` (`OpcacheConfig`) documents the `None`
default as "off otherwise (single-node: `ephpm cache reset` is the right
interface)" — but `ephpm cache reset` (`crates/ephpm/src/main.rs`,
`CacheSubcommand::Reset`) is the same key write as `deploy` and needs that
watcher. Either turn the watcher on whenever `[kv.redis_compat]` is enabled
(the CLI cannot reach the store otherwise anyway), or make `cache reset`
call `opcache_reset()` in the server directly; at minimum the CLI should
warn when the server it talks to is not watching.

### Workaround

The Nextcloud recipe sets `[opcache] cluster_invalidation = true`. Every
other recipe's README tells users to run `docker compose restart ephpm`
after changing PHP code instead (verified against the v0.11.3 source and the
repro above, 2026-10-11). The `[kv.redis_compat]` comments in those
recipes' `ephpm.toml` files still mention `ephpm cache reset`; the listener
is still useful for `ephpm kv ...`.

## 2. `/.well-known/*` is always refused by `hidden_files`

**Severity: low.** `[server.static] hidden_files = "deny"` (the default)
answers 403 for any path with a dot-prefixed segment, which includes
`/.well-known/` (RFC 8615). Nextcloud's `.htaccess` redirects
`/.well-known/carddav` and `/.well-known/caldav` to `/remote.php/dav/`
(CalDAV/CardDAV client auto-discovery), and the admin overview warns about
it; the same applies to `/.well-known/security.txt`, `webfinger`,
`nodeinfo`, `openid-configuration` … in other apps. The request never reaches
`fallback`, so the app cannot answer it either. The only way out is
`hidden_files = "allow"`, which exposes every dotfile in the tree (Nextcloud
ships `.env`, `.user.ini`, `.htaccess` and dozens of vendor dotfiles).

`has_hidden_segment()` in `crates/ephpm-server/src/router.rs` could exempt a
leading `/.well-known/` segment (nginx and Apache configs commonly do
exactly that), or `hidden_files` could take an allow-list.

## 3. (known) `ephpm php` → `headers_sent()` is true: `occ` and `php cron.php` cannot run

Already recorded in `issues/wallabag.md`; noting the Nextcloud impact. Every
`occ` command, and `cron.php` from the CLI, fails while loading the config:

```
$ ephpm php occ status
Exception: Config file has leading content, please remove everything before "<?php" in ephpm.config.php
  in lib/private/Config.php:254   (if (!defined('PHPUNIT_RUN') && headers_sent()) throw …)
```

(with no extra fragment the same happens on `config.php` once installed).
The recipe therefore installs through the web installer (`autoconfig.php`)
and runs background jobs by fetching `/cron.php` over HTTP. Maintenance
mode, `files:scan`, `occ upgrade`, app management from the CLI etc. are not
available until ePHPm stops pre-setting `SG(headers_sent)` in `cli_begin()`.

## 4. (known) no `PATH_INFO`

Already recorded in `issues/espocrm.md`. Nextcloud's WebDAV (`/remote.php/dav/…`),
OCS (`/ocs/v2.php/…`) and public-share (`/public.php/…`) endpoints all depend
on it. The recipe works around it in userland with an `auto_prepend_file`
(`apps/nextcloud/ephpm-pathinfo.php`) that re-dispatches such requests to the
named script with `SCRIPT_NAME`/`SCRIPT_FILENAME`/`PATH_INFO` set the way
`fastcgi_split_path_info` would — a pattern other PATH_INFO apps could reuse
until ePHPm splits the path itself.
