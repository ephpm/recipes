# ePHPm issues found while writing the Kanboard recipe

Found on `ephpm/ephpm:v0.11.3-php8.5`, 2026-10-11.

## Embedded database: `SET FOREIGN_KEY_CHECKS` is forwarded to SQLite; `ALTER DATABASE … CHARACTER SET` and `ALTER TABLE … CONVERT TO CHARACTER SET` are rejected

**Severity: medium (embedded-database compatibility).** Kanboard's MySQL
driver (PicoDb, `libs/picodb/lib/PicoDb/Driver/Mysql.php`) wraps every
migration run in `SET FOREIGN_KEY_CHECKS=0` / `=1`. litewire translates
`SET NAMES …` and `SET sql_mode = …` (even combined:
`SET sql_mode = STRICT_ALL_TABLES, NAMES utf8mb4` works) but passes
`SET FOREIGN_KEY_CHECKS=…` through to Turso untouched, so the very first
request on the embedded database dies with

```
Internal Error: SQLSTATE[HY000]: General error: 1105 SQLite error: near "SET": syntax error
```

Two statements from the migrations are refused by litewire's own parser as
well (they would be hit later, at schema version 131):

```
ALTER DATABASE kanboard CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  → SQL parse error: Expected: one of VIEW or TYPE or TABLE or INDEX or ROLE …, found: DATABASE
ALTER TABLE t CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
  → SQL parse error: Expected: ADD, RENAME, PARTITION, SWAP, DROP, REPLICA IDENTITY, or SET TBLPROPERTIES after ALTER TABLE, found: CONVERT
```

### Minimal repro (stock image, no application)

```bash
# ephpm.toml: [db.sqlite] path = "/tmp/probe.db"  [db.sqlite.proxy] mysql_listen = "127.0.0.1:3306"
ephpm serve --config ephpm.toml &
ephpm php -r '$c = mysqli_connect("127.0.0.1","root","","kanboard",3306);
  foreach (["SET FOREIGN_KEY_CHECKS=0", "SET sql_mode = STRICT_ALL_TABLES, NAMES utf8mb4",
            "ALTER DATABASE kanboard CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci"] as $sql) {
    echo $sql, " => ", mysqli_query($c, $sql) ? "OK" : mysqli_error($c), PHP_EOL; }'
# SET FOREIGN_KEY_CHECKS=0 => SQLite error: near "SET": syntax error
# SET sql_mode = STRICT_ALL_TABLES, NAMES utf8mb4 => OK
# ALTER DATABASE kanboard CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci => SQL parse error: …
```

### Suggested fix (litewire, `ephpm/litewire`)

- `SET FOREIGN_KEY_CHECKS = 0|1` → `PRAGMA foreign_keys = OFF|ON` (or accept
  and ignore it, as MySQL session variables that have no SQLite meaning —
  `SET sql_mode` is already treated that way).
- `ALTER DATABASE … CHARACTER SET …` → no-op success.
- `ALTER TABLE … CONVERT TO CHARACTER SET …` → no-op success (SQLite text is
  always UTF-8).

The recipe therefore ships the MariaDB stack and Kanboard's own SQLite
single container only; the `compose.embedded.yml` variant was removed rather
than published untested. The column-level `CHARACTER SET` gap recorded in
`issues/yourls.md` is separate (Kanboard only uses table-level `CHARSET=`).
