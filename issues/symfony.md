# symfony — embedded DB rejects `ALTER TABLE … ADD CONSTRAINT … FOREIGN KEY`

**App:** Symfony Demo v2.9.0 (Doctrine ORM 3 / DBAL 4, MySQL platform) via
`DATABASE_URL=mysql://root:@127.0.0.1:3306/app` against `[db.sqlite]` +
`[db.sqlite.proxy] mysql_listen`.

**Symptom:** `bin/console doctrine:schema:create` fails:

```
SQLSTATE[HY000]: General error: 1105 SQLite error: near "CONSTRAINT": syntax error
while executing DDL: ALTER TABLE symfony_demo_post ADD CONSTRAINT FK_58A92E65F675F31B
  FOREIGN KEY (author_id) REFERENCES symfony_demo_user (id)
```

The `CREATE TABLE` statements before it succeed; the first `ALTER TABLE …
ADD CONSTRAINT` aborts the schema tool.

**Minimal repro** (any MySQL client against the embedded listener):

```sql
CREATE TABLE a (id INT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE b (id INT AUTO_INCREMENT PRIMARY KEY, a_id INT);
ALTER TABLE b ADD CONSTRAINT fk_b_a FOREIGN KEY (a_id) REFERENCES a (id);
```

**Suspected cause:** litewire's MySQL→SQLite DDL translation passes `ALTER
TABLE … ADD CONSTRAINT` through unchanged; SQLite's `ALTER TABLE` has no
`ADD CONSTRAINT` form (foreign keys can only be declared in `CREATE TABLE`).
Doctrine (and Laravel's schema builder, CodeIgniter migrations, …) emit
foreign keys as a second-pass `ALTER TABLE`, so this blocks the embedded
database for most framework migrations. A translation that either
(a) rewrites the statement into a table rebuild with the constraint added,
or (b) accepts and ignores `ADD CONSTRAINT … FOREIGN KEY` (SQLite does not
enforce FKs unless `PRAGMA foreign_keys=ON` anyway), would unblock them.
Lives in the litewire crate (`github.com/ephpm/litewire`, MySQL frontend
SQL translation), not in ePHPm itself. The same failure was hit by the
BookStack, InvoicePlane and Easy!Appointments recipes.
