# CodeIgniter 4: every 404 / error page is a bare 500 (exit() in the exception handler)

**Recipe:** `apps/opensourcepos` (Open Source POS 3.4.2, CodeIgniter 4.7.4) —
**ePHPm:** `ephpm/ephpm:v0.11.3-php8.4` — **Date:** 2026-10-11

A fourth trigger of the bug recorded in `issues/phpmyadmin.md` (exit from a
shutdown function or an output-buffer callback) and `issues/yii2.md` (exit
from a `set_exception_handler()` callback). Not OSPOS-specific: it is
CodeIgniter 4's own exception handler, so every CI4 application on ePHPm is
affected (`apps/codeigniter4` very likely too; not re-checked here).

## Symptom

Any request that ends in an exception — including every unknown route,
which CI4 turns into a `PageNotFoundException` — answers

```
HTTP/1.1 500 Internal Server Error
PHP execution error: PHP script bailed out (truncated response discarded): /app/public/index.php (GET /nope)
```

and ePHPm logs `PHP script terminated in a Zend bailout … truncated response
discarded, returning 500`. Apache/php-fpm send CodeIgniter's rendered 404
page with status 404.

## Cause

`vendor/codeigniter4/framework/system/Debug/ExceptionHandler.php`,
`handle()`: after rendering the error view (or the JSON body for non-HTML
`Accept`), it calls `exit($exitCode)` when `ENVIRONMENT !== 'testing'`.
`Exceptions::exceptionHandler()` is installed with `set_exception_handler()`,
so the exit runs with no calling frame and ePHPm's
`ephpm_bailout_observed()` (`crates/ephpm-php/ephpm_wrapper.c`) treats the
resulting `zend_bailout()` as fatal — exactly the mechanism and suggested
fix described in `issues/yii2.md`.

## Minimal repro

The three-line `x1.php` in `issues/yii2.md` reproduces it without any
framework. With OSPOS: `curl -i http://127.0.0.1:8080/nope` → 500.

## Workaround in the recipe

The Dockerfile rewrites the two `if (ENVIRONMENT !== 'testing') {` guards in
`ExceptionHandler.php` to `if (ENVIRONMENT !== 'testing' && is_cli()) {`
(build fails if the code no longer matches), so on the web the handler
returns after rendering and the 404/500 page is delivered with its status;
on the CLI (`spark`) the exit code is kept. Remove once ePHPm is fixed.
