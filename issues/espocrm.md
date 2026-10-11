## espocrm, ojs: no per-prefix fallback (nginx `location`) and no `PATH_INFO`

**Apps:** EspoCRM 10.0.9 (`apps/espocrm`) and OJS 3.5.0-4 (`apps/ojs`); the
same two gaps will show up in any app whose web-server config has more than
one rewrite target or routes by `PATH_INFO` (SuiteCRM 8, Moodle, MediaWiki
with short URLs, Dolibarr's `index.php/…` links, WordPress "PATHINFO"
permalinks).

**Two things nginx/Apache do that `[server] fallback` cannot express:**

1. **Several rewrite targets, chosen by path prefix.** EspoCRM's nginx config
   is `location /api/v1/ { rewrite ^ /api/v1/index.php }`,
   `location /portal/ { … /portal/index.php }`, `location /client { root <app> }`,
   and `try_files $uri /index.php` for the rest. `fallback` is one chain for
   the whole site, so there is no way to say "under `/api/v1/` fall back to
   `/api/v1/index.php` instead".
2. **`PATH_INFO`.** Apache's `AcceptPathInfo On` + `RewriteRule ^(.*)$
   index.php/$1` (OJS, and the `/index.php/<rest>` URL style CodeIgniter and
   Symfony also accept) hands `index.php` the trailing path in
   `$_SERVER['PATH_INFO']`. ePHPm never sets `PATH_INFO`
   (`crates/ephpm-php` has no reference to it) and does not split a request
   path at the first `.php` segment the way `fastcgi_split_path_info
   ^(.+\.php)(/.+)$` does, so `/index.php/journal/login` is just a missing
   file that falls through to `/index.php` with an unusable path. OJS builds
   its request path from `SCRIPT_NAME . PATH_INFO` (`PKPRequest::getRequestPath`)
   and sees `/` for every URL. CodeIgniter apps survive because they parse
   `REQUEST_URI` themselves.

**Workaround in both recipes:** a 30-line PHP front controller
(`apps/espocrm/front.php`, `apps/ojs/front.php`) is the single fallback
target. It picks the entry point by prefix and/or computes `PATH_INFO` from
`REQUEST_URI`, sets `SCRIPT_NAME`/`PHP_SELF`/`SCRIPT_FILENAME` the way
php-fpm would for that script, `chdir()`s to its directory (the entry points
`require` with relative paths) and `require`s it. It works, but every such
app needs its own shim, and `SCRIPT_NAME` lies to PHP about which file is
running.

**Suggested ePHPm features:**

- `[server] fallback` entries scoped by prefix, e.g. a `[[server.route]]`
  table with `prefix = "/api/v1/"` and its own `fallback`, evaluated longest
  prefix first before the global chain. That is the `location` block most
  nginx configs in the wild reduce to.
- `PATH_INFO` support: when a request path has no file but a leading part of
  it (`/index.php`, `/foo/bar.php`) is a PHP file, execute that file with
  `PATH_INFO` (and `PATH_TRANSLATED`, `ORIG_PATH_INFO`) set to the remainder
  and `SCRIPT_NAME` to the script part — php-fpm's `fastcgi_split_path_info`
  behaviour, which the fallback chain could also opt into with a
  `"/index.php$path_info"` variable.
