# `filter_has_var(INPUT_SERVER, …)` / `filter_input(INPUT_SERVER, …)` never see $_SERVER

**Recipe:** `apps/ampache` (Ampache 8.2.2) — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.5` — **Date:** 2026-10-11

**Severity: high for affected apps.** Under `ephpm serve`, the filter
extension's copy of the server variables is empty: `$_SERVER['REMOTE_ADDR']`
is set, but `filter_has_var(INPUT_SERVER, 'REMOTE_ADDR')` is `false` and
`filter_input(INPUT_SERVER, 'REMOTE_ADDR')` is `NULL`. `INPUT_GET` and
`INPUT_ENV` work.

Ampache reads the client IP that way (`Core::get_user_ip()`), gets `''`, and
its access-control list then refuses **every** page, the login page
included: "Access Denied — is not in the Interface Access list". Any app
that uses `filter_input(INPUT_SERVER, …)` for `REQUEST_METHOD`,
`HTTP_HOST`, `HTTPS`, `REMOTE_ADDR`, … (a common "don't touch superglobals"
style, e.g. in WordPress plugins and PHPCS-clean code) gets nulls.

## Minimal repro (stock image)

```php
<?php // zz.php, served by `ephpm serve`
var_dump(filter_has_var(INPUT_SERVER, "REMOTE_ADDR"), filter_input(INPUT_SERVER, "REMOTE_ADDR"),
         $_SERVER["REMOTE_ADDR"] ?? null, filter_has_var(INPUT_GET, "a"));
```

`curl 'http://127.0.0.1:8080/zz.php?a=1'` →
`bool(false) NULL string(9) "10.89.4.5" bool(true)`. php-fpm / Apache:
`bool(true) string(...) "…" bool(true)`.

## Suspected cause

`crates/ephpm-php/ephpm_wrapper.c`, `ephpm_sapi_register_server_variables()`:
it calls `php_register_variable_safe()` for each server variable directly.
Every stock SAPI (cgi/fpm `cgi_php_import_environment_variables` +
`sapi_cgi_register_variables`, apache2handler, cli) first passes the value
through `sapi_module.input_filter(PARSE_SERVER, var, &val, len, &new_len)`
and registers only what it returns. ext/filter's `php_sapi_filter()` is that
hook: for `PARSE_SERVER` it stores a raw copy in `IF_G(server_array)`, which
is what `filter_has_var`/`filter_input(INPUT_SERVER, …)` read. Skipping the
hook leaves that array empty (and also bypasses any `filter.default`
sanitising of server vars).

Suggested fix: in the loop, do what `sapi_cgi_register_variables()` does —

```c
size_t new_len;
char *val = estrdup(value);
if (sapi_module.input_filter(PARSE_SERVER, key, &val, strlen(val), &new_len)) {
    php_register_variable_safe(key, val, new_len, track_vars_array);
}
efree(val);
```

(and the same in the CLI path's `$_SERVER` registration), plus an E2E case
asserting `filter_input(INPUT_SERVER, 'REQUEST_METHOD') === 'GET'`.

## Workaround in the recipe

The Dockerfile rewrites the two `filter_has_var(INPUT_SERVER, '…')` calls in
`src/Module/System/Core.php` to `isset($_SERVER['…'])` (build fails if the
code changes). Remove once ePHPm is fixed.
