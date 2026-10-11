## wallabag: `ephpm php` reports `headers_sent()` as true before any output, so `session_start()` fails in CLI commands

**App:** wallabag 2.6.14, recipe `apps/wallabag`. Not wallabag-specific — any
console command that starts a PHP session hits it (Symfony `NativeSessionStorage`,
FOSUserBundle event listeners, CodeIgniter/Laravel artisan commands that touch
the session).

**Symptom:** `wallabag:install --no-interaction` creates the schema but the
admin-user step dies with

```
In NativeSessionStorage.php line 152:
  Failed to start the session because headers have already been sent by "" at line 0.
Warning: ini_set(): Session ini settings cannot be changed after headers have already been sent in .../NativeFileSessionHandler.php on line 52
```

and no user is created (the official image, running the same command under
php-cli, creates `wallabag`/`wallabag`). `fos:user:create` fails the same way
(after persisting the user, so it leaves a user without its `Config` row).

**Minimal repro** (no app involved):

```bash
ephpm php -r 'var_dump(headers_sent($f, $l), $f, $l); var_dump(@session_start());'
# bool(true)  string(0) ""  int(0)  bool(false)      <- ephpm php (v0.11.3, PHP 8.4 and 8.5 images)
# bool(false) string(0) ""  int(0)  bool(true)       <- stock php-cli
```

**Cause:** `crates/ephpm-php/ephpm_wrapper.c`, `cli_begin()` (around line
6005):

```c
    SG(headers_sent) = 1;
    SG(request_info).no_headers = 1;
```

The comment says this is "so PHP doesn't try to emit HTTP headers". php-cli
achieves that differently: its SAPI `send_headers` callback returns
`SAPI_HEADER_SENT_SUCCESSFULLY` without writing anything and leaves
`SG(headers_sent)` at 0 until the script actually produces output, so
`headers_sent()` is `false` at script start and `session_start()` (which
refuses to start a cookie session when `SG(headers_sent)` is set, and whose
`session.*` ini handlers reject changes in the same state) works. Setting the
flag up front makes every "have headers been sent?" check in userland and in
the session extension answer "yes" before a byte was written.

**Suggested fix:** drop the `SG(headers_sent) = 1` in `cli_begin()` (keep
`no_headers = 1`) and make the CLI path's `send_headers`/`header_handler`
no-ops, as php-cli's `sapi_cli_send_headers` does; `headers_sent()` then
turns true on first output exactly like php-cli. A test: `ephpm php -r
'var_dump(headers_sent(), session_start());'` must print `false`/`true`.

**Workaround in the recipe:** the `wallabag` console wrapper passes
`-d session.use_cookies=0`. Both PHP's `php_session_start()` and Symfony's
`NativeSessionStorage::start()` only refuse when `session.use_cookies` is on,
and a cookieless session is fine for a CLI run. The `ini_set()` warnings for
`session.save_path` still appear (harmless: the CLI session lands in the
default temp dir). The README documents it.
