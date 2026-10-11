# ePHPm issues found while writing the Yii 2 recipe

Found on `ephpm/ephpm:v0.11.3-php8.5` (PHP 8.5.7), 2026-10-11, with
`yiisoft/yii2-app-basic` 2.0.54 (framework 2.0.55).

## 1. `exit()` inside a `set_exception_handler()` handler → bare 500, rendered page discarded

**Severity: high for Yii 2 (every error page, 404s included).** A third
trigger of the bug recorded in `issues/phpmyadmin.md` (exit from a shutdown
function or an output-buffer callback). Yii 2's
`yii\base\ErrorHandler::handleException()` renders the error page (the
`site/error` action, with the app layout, and the right status: 404 for an
unknown route, 400 for a bad CSRF token) and then calls `exit(1)`. ePHPm
answers every such request with

```
HTTP/1.1 500 Internal Server Error
PHP execution error: PHP script bailed out (truncated response discarded): /app/web/index.php (GET /site/nope)
```

and logs `PHP script terminated in a Zend bailout … discarded_body_bytes=3303`.
php-fpm sends the rendered 404 page.

### Minimal repro (stock image, no application)

```php
<?php // x1.php
set_exception_handler(function ($e) { http_response_code(500); echo "handled: ", $e->getMessage(); exit(1); });
throw new Exception("boom");
```

```
x1.php  (handler echoes, then exit(1))  → 500, body "PHP execution error: PHP script bailed out …"
x2.php  (same handler without exit)     → 500, body "handled: boom"
x3.php  (echo "a"; exit(1);)            → 200, body "a"
```

### Why (verify before acting)

An `exit()` in a userland callback that the engine calls with no calling
frame (exception handler, shutdown function, ob callback) ends in a real
`zend_bailout()` in stock PHP too: the unwind-exit propagates out of
`zend_call_function()` with `EG(current_execute_data) == NULL`, and
`zend_throw_exception_internal()` reports it (a no-op for unwind-exit) and
bails out. php-fpm ignores that — `php_execute_script()`'s `zend_try`
absorbs it and the output is sent. ePHPm's `ephpm_bailout_observed()`
(`CG(unclean_shutdown) != 0`, `crates/ephpm-php/ephpm_wrapper.c`, around
line 1354) treats every such jump as a fatal bailout and discards the
capture. A bailout with no fatal recorded (`PG(last_error_type)` not in the
fatal mask) and no memory/timeout error is an `exit()`, and the response is
complete; the fix suggested in `issues/phpmyadmin.md` should cover this
call site as well.

### Workaround used by the recipe

`config/web.php` sets `errorHandler.silentExitOnException = true` (a
documented Yii 2 property), which skips that `exit(1)`; the error page and
its status code are then delivered. Remove it once ePHPm is fixed.

## 2. Embedded database: `SHOW FULL COLUMNS` / `SHOW CREATE TABLE` on a missing table return an empty set instead of error 1146

**Severity: medium (embedded-database compatibility).** Yii 2's MySQL schema
reader checks whether a table exists by running `SHOW FULL COLUMNS FROM t`
and catching SQLSTATE `42S02` (MySQL error 1146). litewire answers that
statement with an empty result set for a table that does not exist, so Yii
goes on to `SHOW CREATE TABLE t`, which is also an empty set, and dies:

```
$ ephpm php yii migrate/history --interactive=0
Exception 'TypeError' with message 'array_values(): Argument #1 ($array) must be of type array, false given'
in /app/vendor/yiisoft/yii2/db/mysql/Schema.php:417
  #1 Schema->getCreateTableSql()  #2 Schema->getJsonColumns()  #3 Schema->findColumns()
  #4 Schema->loadTableSchema('migration')  … MigrateController->getMigrationHistory()
```

So `yii migrate` (and any `getTableSchema()` on a table that is not there
yet) cannot run on the first start against the embedded database.

### Minimal repro (`[db.sqlite]` + `[db.sqlite.proxy] mysql_listen = "127.0.0.1:3306"`)

```php
$p = new PDO("mysql:host=127.0.0.1;port=3306;dbname=x", "root", "", [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
$p->query("SHOW FULL COLUMNS FROM `nosuch`")->fetchAll();  // [] — MySQL: SQLSTATE[42S02] 1146
$p->query("SHOW CREATE TABLE `nosuch`")->fetchAll();       // [] — MySQL: SQLSTATE[42S02] 1146
$p->query("SELECT * FROM `nosuch`");                        // SQLSTATE[42S02] 1146 (correct)
```

Two smaller differences seen on an existing table, same listener:
`SHOW FULL COLUMNS` reports `Extra` as `""` for an `AUTO_INCREMENT` primary
key (MySQL: `auto_increment`), and `SHOW CREATE TABLE` returns only the
`Create Table` column (MySQL also returns `Table`).

### Suspected cause

litewire's MySQL frontend emulates `SHOW [FULL] COLUMNS` / `SHOW CREATE
TABLE` from `pragma_table_info` / `sqlite_schema`, which yield zero rows for
an unknown table instead of an error. It should raise
`ER_NO_SUCH_TABLE` (1146, SQLSTATE `42S02`) when the table is not in
`sqlite_schema`. Lives in `github.com/ephpm/litewire`, not ePHPm itself.

### Outcome

The recipe ships the MariaDB stack only. Even with this fixed, Yii
migrations that use `addForeignKey()` would hit the known
`ALTER TABLE … ADD CONSTRAINT` gap (`issues/symfony.md`).
