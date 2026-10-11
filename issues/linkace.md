# LinkAce: embedded database variant not shipped (schema dump DDL)

**Recipe:** `apps/linkace` — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.5` — **Date:** 2026-10-11

## What was tried

`compose.embedded.yml` with `[db.sqlite] path = ...` + `[db.sqlite.proxy]
mysql_listen = "127.0.0.1:3306"`, LinkAce 2.6.2 (Laravel 11) pointed at it
(`DB_HOST=127.0.0.1 DB_USERNAME=root DB_PASSWORD=""`), setup wizard's
database step (which runs `artisan migrate:fresh`).

## What happened

LinkAce ships a pruned migration set plus a schema dump
(`database/schema/mysql-schema.dump`, written by `artisan schema:dump
--prune`). Laravel loads such a dump by piping it through the `mysql` CLI
(`MySqlSchemaState::load`), so the image installs `mariadb-client` (as the
official LinkAce base image does). Against MariaDB that works. Against the
embedded listener the very first statement of the dump fails:

```
CREATE TABLE `failed_jobs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `connection` text COLLATE utf8mb4_bin NOT NULL,
  ...
  `failed_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin
ERROR 1105 (HY000) at line 10: SQLite error: near "(": syntax error
```

## Minimal repro (mysql CLI against `[db.sqlite.proxy] mysql_listen`)

```
mysql --user=root --host=127.0.0.1 --port=3306 --database=x -e "..."

-- OK: Laravel-grammar style
create table td (id bigint unsigned not null auto_increment primary key, q text not null, created_at timestamp null)
-- OK: display width + table options
create table ta (id bigint(20) unsigned not null auto_increment, primary key (id)) engine=InnoDB

-- FAIL: MariaDB dump spelling of the default (parentheses)
create table tb (id bigint unsigned not null auto_increment primary key, f timestamp not null default current_timestamp())
  -> ERROR 1105 (HY000): SQLite error: near "(": syntax error

-- FAIL: column/table collation names
create table tc (id bigint unsigned not null auto_increment primary key, q text collate utf8mb4_bin not null) engine=InnoDB default charset=utf8mb4 collate=utf8mb4_bin
  -> ERROR 1105 (HY000): SQLite error: Parse error: no such collation sequence: utf8mb4_bin
```

## Suspected cause

litewire's MySQL→SQLite DDL translation handles what Laravel's grammar
emits but not what `mysqldump`/`mariadb-dump` writes back out:

1. `DEFAULT current_timestamp()` — MariaDB prints the function with
   parentheses; SQLite only accepts `CURRENT_TIMESTAMP` as a bare keyword
   default (or `(expr)` parenthesised as a whole). The translator should map
   `current_timestamp()` / `CURRENT_TIMESTAMP()` → `CURRENT_TIMESTAMP`.
2. `COLLATE utf8mb4_bin` / `utf8mb4_unicode_ci` (column and table level)
   is passed through; SQLite knows only `BINARY`, `NOCASE`, `RTRIM`. The
   translator should drop MySQL collations (or map `*_bin` → `BINARY`,
   `*_ci` → `NOCASE`).

Both are generic: every Laravel app that ships a `schema:dump` (Laravel's
recommended way to squash migrations) hits (1) and (2) on first install
against the embedded database, with the schema dump being the only route
once migrations have been pruned. Fixing both would likely let the LinkAce
dump load; whether the rest of it (`/*!40101 ... */` conditional comments,
`SET FOREIGN_KEY_CHECKS`, `KEY`/`UNIQUE KEY` index clauses inside
`CREATE TABLE`) also translates was not verified because the first table
already fails.

## Outcome

Only `compose.yml` (MariaDB) is shipped for LinkAce. The README says the
embedded variant is not offered and why. `[kv.redis_compat]` still works for
cache/sessions on the MariaDB stack (`CACHE_DRIVER=redis SESSION_DRIVER=redis
REDIS_HOST=127.0.0.1`), but that combination is not exercised by `test.sh`.
