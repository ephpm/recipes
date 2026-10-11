# LimeSurvey: `exit()` inside an exception handler is a bailout → every error page (404, 403, …) becomes a bare 500

**Recipe:** `apps/limesurvey` — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.5` — **Date:** 2026-10-11

Same root cause as the shutdown-function / output-callback case in
[`issues/phpmyadmin.md`](phpmyadmin.md), reached through a third entry
point: the handler installed with `set_exception_handler()`.

## Symptom

Any LimeSurvey URL that ends in an exception — an unknown route
(`/nonexistent-page`), a `CHttpException(403/404)` from a controller —
answers

```
500  PHP execution error: PHP script bailed out (truncated response discarded): /var/www/html/index.php (GET /nonexistent-page)
ERROR ephpm_php: PHP script terminated in a Zend bailout (out of memory, a resource limit,
  or an extension calling zend_bailout()) — truncated response discarded, returning 500
```

instead of LimeSurvey's rendered 404/403 page. Yii 1's
`CApplication::handleException()` (the registered exception handler)
renders the error view and then calls `$this->end(1)` → `exit(1)`. Normal
pages are unaffected; the app's real workflows pass.

## Minimal repro (stock image, no application)

```php
<?php // exh.php
set_exception_handler(function ($e) { http_response_code(404); echo "handled: ", $e->getMessage(); exit(1); });
throw new Exception("not found");
```

```
exh.php   (handler calls exit)       → 500, body discarded
exh2.php  (same handler, no exit)    → 404 "handled: not found"
ephpm php exh.php                    → "handled: not found", exit status 1 (CLI is fine)
```

php-fpm / `php -S` return 404 with the body for both.

## Suspected cause

`crates/ephpm-php/ephpm_wrapper.c`: the user exception handler runs from
`zend_execute_scripts()` after the script's top frame has unwound, i.e. with
no `current_execute_data`, so `exit()` inside it ends in `zend_bailout()`
exactly as described for shutdown functions in `issues/phpmyadmin.md`;
`ephpm_bailout_observed()` then forces the 500 and discards the capture. A
fix for that issue should treat an unwind-exit raised from the user
exception handler the same way (deliver the captured status and body) —
worth adding this script to the same E2E case.

## Workaround

None in the recipe (patching Yii's `CApplication::end()` out of the error
path would change behaviour for every request). Documented in the README as
a known limitation: error pages are ePHPm's bare 500.
