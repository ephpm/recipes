# ePHPm issues found while writing the phpMyAdmin recipe

Found on `ephpm/ephpm:v0.11.3-php8.5`, 2026-10-11.

## `exit()` inside a shutdown function (or an output-buffer callback) is reported as a Zend bailout → 500, finished response discarded

**Severity: high (application compatibility).** php-fpm delivers the output
of a script whose `register_shutdown_function()` callback calls `exit()`;
ePHPm answers **500** and throws the already-rendered body away:

```
ERROR ephpm_php: PHP script terminated in a Zend bailout (out of memory, a resource limit,
  or an extension calling zend_bailout()) — truncated response discarded, returning 500
  script=/var/www/html/index.php method=GET uri=/ discarded_body_bytes=18578 output_tail=…login form…
```

No PHP error is logged, because nothing went wrong from PHP's point of view.

### Minimal repro (stock image, no application)

```php
<?php // shutdown-exit.php
register_shutdown_function(function () { exit; });
echo "shutdown-exit ok";
```

```
plain-exit.php        (echo …; exit;)                               → 200 "plain-exit ok"
shutdown-exit.php     (shutdown fn calls exit)                      → 500, body discarded
ob-shutdown-exit.php  (ob_start; shutdown fn: ob_end_flush(); exit) → 500, body discarded
ob-callback-exit.php  (ob_start callback calls exit)                → 500, body discarded
```

Served with `ephpm serve` (`document_root` pointing at the four files);
`php -S` / php-fpm return 200 with the body for all four.

### Why (verify before acting)

`crates/ephpm-php/ephpm_wrapper.c`, request execution: a top-level `exit()`
is recognised after `php_execute_script()` via
`zend_is_unwind_exit(EG(exception))` and treated as an intentional exit.
Shutdown functions and `php_output_end_all()` are then run under
`zend_try { … } zend_catch { … }`. An `exit()` *there* throws the unwind
exception inside `zend_call_function()` with no `current_execute_data`, so
`zend_throw_exception_internal(NULL)` ends in `zend_bailout()` — which sets
`CG(unclean_shutdown) = 1`. The wrapper's 500 decision then reads
`ephpm_bailout_observed()` ("a bailout forces 500 UNCONDITIONALLY … it is
never something a script asks for") and discards the capture. For an exit
raised from a shutdown function that assumption is wrong: it *is* something
the script asked for, and the response is complete.

Suggested fix: in the `zend_catch` arms around `php_call_shutdown_functions()`
and `php_output_end_all()`, check for an unwind-exit before treating the
jump as a bailout (e.g. snapshot `EG(exit_status)`/`EG(flags) &
EG_FLAGS_IN_SHUTDOWN`, or clear `CG(unclean_shutdown)` when the pending
exception was an unwind exit), and keep delivering the capture. Pin it with
the four scripts above as an E2E case.

### Impact

phpMyAdmin renders **every** page from a shutdown function:
`ResponseRenderer::__construct()` does
`register_shutdown_function([$this, 'response'])`, and `response()` ends
with `$buffer->flush(); exit;`. So on ePHPm v0.11.3 every phpMyAdmin page is
a 500 (the login form was fully rendered — 18 578 bytes — and discarded).
Other apps that exit from shutdown functions or ob callbacks (some
framework fatal handlers, maintenance-mode plugins) will hit the same wall.

### Workaround used by the recipe

The Dockerfile rewrites that one `exit;` in
`libraries/classes/ResponseRenderer.php::response()` to `return;`
(guarded by `grep` so a phpMyAdmin release that changes the code fails the
build instead of silently shipping unpatched). Inside the shutdown function
a `return` is equivalent: the remaining shutdown function
(`OutputBuffering::stop`) returns early because `response()` already
stopped the buffer. Remove the patch once ePHPm is fixed.
