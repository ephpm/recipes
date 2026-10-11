## invoiceplane: `ALTER TABLE … MODIFY / CHANGE / … AFTER col / ADD PRIMARY KEY` fail on the embedded database

**App:** InvoicePlane 1.7.2 (CodeIgniter 3, `mysqli` driver), recipe `apps/invoiceplane`.

**Symptom:** with `[db.sqlite]` + `[db.sqlite.proxy] mysql_listen`,
`ephpm php index.php setup/cli/migrate` creates the base tables
(`000_1.0.0.sql`, plain `CREATE TABLE … ENGINE=MyISAM`) but the upgrade
migrations (`003_1.1.0.sql`, `006_1.2.0.sql`, `008_1.3.0.sql`,
`012_1.4.0.sql`, `019_1.4.7.sql`, …) fail with dozens of

```
SQLite error: near "MODIFY": syntax error
SQLite error: near "AFTER": syntax error
SQLite error: near "CHANGE": syntax error
SQLite error: near "PRIMARY": syntax error
SQL parse error: sql parser error: Expected: PRIMARY, UNIQUE, FOREIGN, or CHECK, found: ( at Line: 10, Column: 25
```

and the follow-on `no such table: ip_products` once a `CREATE TABLE` inside a
failed batch is skipped. The same migrations complete on MariaDB 11.

**Statement shapes that fail** (all MySQL-only `ALTER TABLE` syntax):

```sql
ALTER TABLE `ip_email_templates` ADD `email_template_from_name` VARCHAR(255) AFTER `email_template_title`;
ALTER TABLE `ip_invoices` MODIFY `invoice_date_created` DATE NOT NULL;
ALTER TABLE `ip_users` CHANGE `user_psalt` `user_psalt` TEXT NOT NULL;
ALTER TABLE `ip_products` ADD PRIMARY KEY (`product_id`);
ALTER TABLE `ip_x` ADD `a` INT, ADD `b` INT;              -- several ADDs in one statement
```

**Minimal repro** (any `[db.sqlite]` single-node config with the MySQL
listener on):

```php
$m = new mysqli('127.0.0.1', 'root', '', 'x', 3306);
$m->query('CREATE TABLE t (id INT NOT NULL AUTO_INCREMENT, a VARCHAR(10), PRIMARY KEY (id))');
$m->query('ALTER TABLE t ADD b INT AFTER a');          // near "AFTER": syntax error
$m->query('ALTER TABLE t MODIFY a VARCHAR(50) NOT NULL'); // near "MODIFY": syntax error
$m->query('ALTER TABLE t CHANGE a a TEXT');            // near "CHANGE": syntax error
```

**Suspected cause:** litewire's MySQL→SQLite translation (git dependency
pinned in the workspace `Cargo.toml`; wired by `crates/ephpm-server/src/lib.rs`
for the `[db.sqlite.proxy]` MySQL frontend) only rewrites the `CREATE TABLE`
dialect; `ALTER TABLE` clauses that SQLite has no grammar for are passed
through. The cheap wins — strip `AFTER col`/`FIRST` from `ADD COLUMN`, split a
multi-`ADD` statement into several, and treat `MODIFY`/`CHANGE` of a column's
type as a no-op (SQLite is dynamically typed) when the column name does not
change — would cover every statement in InvoicePlane's 44 migrations except
`ADD PRIMARY KEY`, which needs a table rebuild.

**Status in the recipe:** only `compose.yml` (MariaDB) is shipped; the README
says the embedded variant is not available and points here.
