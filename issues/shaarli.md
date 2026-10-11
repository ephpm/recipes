# ePHPm issues found while writing the Shaarli recipe

Found on `ephpm/ephpm:v0.11.3-php8.5`, 2026-10-11.

## `[server.security] allowed_php_paths` is matched against the request URI, not the executed script

**Severity: low (usability / docs).** Shaarli's official nginx config executes
exactly one PHP file, `index.php`, and routes every other path to it
(`try_files _ /index.php$is_args$args`). The natural ePHPm spelling is

```toml
[server.security]
allowed_php_paths = ["/index.php"]
```

but with it `GET /` and `GET /login` answer **403** while `GET /index.php`
answers 302 as expected. `Router::is_php_allowed(&uri_path)`
(`crates/ephpm-server/src/router.rs`, called from the `Resolved::File` arm)
receives the *request* path, so a request that reaches `index.php` through
`index_files` or the `fallback` rewrite is compared as `/` or `/login` and
refused. For any front-controller application the knob is therefore unusable:
the only allowed requests are those that literally name the script.

The config reference says "only matching PHP paths execute" — either the check
should run on the resolved script path relative to the document root (what
"PHP paths" suggests, and what makes `["/index.php"]` mean "only the front
controller may execute"), or the docs should say it is the request URI.

Repro: build `apps/shaarli` with the `allowed_php_paths` line above and run
`curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/login` → 403.

Workaround used by the recipe: no `allowed_php_paths`; the directories that
only hold PHP (`/application/*`, `/inc/*`, `/vendor/*`) plus the two top-level
scripts and `/plugins/*/*.php` are listed in `blocked_paths` instead.
