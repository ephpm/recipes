# ePHPm issues found while writing the YOURLS recipe

Found on `ephpm/ephpm:v0.11.3-php8.5`, 2026-10-11.

## Embedded database: column-level `CHARACTER SET` / `COLLATE` in `CREATE TABLE` are not translated

**Severity: medium (embedded-database compatibility).** litewire's MySQL →
SQLite translation strips table-level `DEFAULT CHARSET=… COLLATE=…`,
`ENGINE=…` and `AUTO_INCREMENT=…`, but passes **column-level** charset and
collation clauses through to Turso untouched:

```
CREATE TABLE t2 (k varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '')
  → SQLite error: near "SET": syntax error
CREATE TABLE t3 (k varchar(100) COLLATE utf8mb4_bin NOT NULL)
  → SQLite error: Parse error: no such collation sequence: utf8mb4_bin
```

while these all succeed:

```
CREATE TABLE t1 (k varchar(100) NOT NULL, PRIMARY KEY (k)) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin
CREATE TABLE t4 (id int NOT NULL AUTO_INCREMENT, PRIMARY KEY (id)) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4
SET NAMES utf8mb4
SET sql_mode = ""
SELECT VERSION()   → 8.0.36-litewire
```

### Minimal repro (stock image, no application)

```bash
# ephpm.toml: [db.sqlite] path = "/tmp/probe.db"  [db.sqlite.proxy] mysql_listen = "127.0.0.1:3306"
ephpm serve --config ephpm.toml &
ephpm php -r '$c = mysqli_connect("127.0.0.1","root","","probe",3306);
  var_dump(mysqli_query($c, "CREATE TABLE t2 (k varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL)"), mysqli_error($c));'
# bool(false) "SQLite error: near \"SET\": syntax error"
```

### Impact

YOURLS's installer (`includes/functions-install.php::yourls_create_sql_tables`)
declares `keyword varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin` and
`url text CHARACTER SET utf8mb4 COLLATE utf8mb4_bin` on the `yourls_url` table,
so `/admin/install.php` dies with
`PDOException: SQLSTATE[HY000]: General error: 1105 SQLite error: near "SET"`
on the embedded database. The recipe therefore ships **only** the MariaDB
stack; the `compose.embedded.yml` variant was removed rather than published
untested.

FreshRSS's MySQL schema uses the same construct (`url VARCHAR(32768)
CHARACTER SET latin1 COLLATE latin1_bin`, `guid … CHARACTER SET latin1 COLLATE
latin1_bin`), so its embedded variant is affected identically.

### Suggested fix (litewire, `ephpm/litewire`)

In the DDL rewriter, drop `CHARACTER SET <name>` / `CHARSET <name>` and map
`COLLATE <mysql-collation>` on a column to one of SQLite's `BINARY` /
`NOCASE` (`*_bin` → `BINARY`, `*_ci` → `NOCASE`, else drop), the same way the
table-level options are already handled. A unit test with the two statements
above would pin it.

## (also) `display_errors` is on in v0.11.3 `serve`

The fatal above was rendered **into the HTTP response** — the installer page
began with `Fatal error: Uncaught PDOException … in
/var/www/html/includes/vendor/aura/sql/src/AbstractExtendedPdo.php:556`, full
filesystem path included. The config reference says the `display_errors=Off`
default lands only after v0.11.3; every recipe here now sets
`[php] ini_overrides = [["display_errors","Off"],["log_errors","On"]]`
explicitly. Worth calling out in the v0.11.3 release notes / upgrade guide.
