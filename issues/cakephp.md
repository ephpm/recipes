# cakephp — embedded DB rejects `SHOW FULL TABLES FROM … WHERE TABLE_TYPE IN (…)`

**App:** CakePHP 5.4 `cakephp/app` skeleton + cakephp/migrations 5 (Phinx)
with `DATABASE_URL=mysql://root:@127.0.0.1:3306/cake` against `[db.sqlite]` +
`[db.sqlite.proxy] mysql_listen`. The MySQL connection itself succeeds
(`mysqli_connect` → true).

**Symptom:** every migrations command (`bin/cake.php migrations status|migrate`)
fails before touching the schema:

```
SQLSTATE[HY000]: General error: 1105 SQLite error: near "SHOW": syntax error
Query: SHOW FULL TABLES FROM `cake` WHERE TABLE_TYPE IN ('BASE TABLE', 'VIEW')
  (vendor/cakephp/cakephp/src/Database/Schema/SchemaDialect.php:410 → listTables)
```

**Minimal repro** (any MySQL client against the embedded listener):

```sql
SHOW FULL TABLES FROM `cake` WHERE TABLE_TYPE IN ('BASE TABLE', 'VIEW');
```

**Suspected cause:** litewire's MySQL frontend translates `SHOW TABLES` but
not the `SHOW FULL TABLES FROM <db> WHERE …` form CakePHP's MySQL schema
dialect uses to list tables (it needs the `Table_type` column to tell views
apart). Translating it to
`SELECT name AS Tables_in_<db>, 'BASE TABLE' AS Table_type FROM sqlite_schema WHERE type IN ('table','view')`
(mapping `view` → `'VIEW'`) would unblock CakePHP's ORM/migrations — and
probably Phinx-based tools generally. Lives in `github.com/ephpm/litewire`
(MySQL frontend SHOW emulation), not in ePHPm itself.

**Outcome:** the recipe ships the MariaDB stack only; no embedded variant.
