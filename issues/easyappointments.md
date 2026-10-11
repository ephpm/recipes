## easyappointments: `ALTER TABLE … ADD CONSTRAINT … FOREIGN KEY` fails on the embedded database

**App:** Easy!Appointments 1.6.0 (CodeIgniter 3, `mysqli` driver), recipe `apps/easyappointments`.

**Symptom:** with `[db.sqlite]` + `[db.sqlite.proxy] mysql_listen` the web
installer (`POST /index.php/installation/perform`) fails inside CodeIgniter's
migration runner at `application/migrations/001_specific_calendar_sync.php:384`
with

```
mysqli_sql_exception: SQLite error: near "CONSTRAINT": syntax error (code 1105)
```

The statement that fails:

```sql
ALTER TABLE `ea_appointments`
  ADD CONSTRAINT `ea_appointments_ibfk_2` FOREIGN KEY (`id_users_customer`) REFERENCES `ea_users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `ea_appointments_ibfk_3` FOREIGN KEY (`id_services`) REFERENCES `ea_services` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `ea_appointments_ibfk_4` FOREIGN KEY (`id_users_provider`) REFERENCES `ea_users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
```

The `CREATE TABLE` statements before it (MySQL types, `ENGINE=InnoDB`,
`AUTO_INCREMENT`) all translate fine; the first migration that adds foreign
keys after the fact is where it stops. The same install completes on MariaDB 11.

**Minimal repro** (any `[db.sqlite]` single-node config with the MySQL
listener on, `mysqli` client):

```php
$m = new mysqli('127.0.0.1', 'root', '', 'x', 3306);
$m->query('CREATE TABLE a (id INT NOT NULL AUTO_INCREMENT, PRIMARY KEY (id)) ENGINE=InnoDB');
$m->query('CREATE TABLE b (id INT NOT NULL AUTO_INCREMENT, a_id INT, PRIMARY KEY (id)) ENGINE=InnoDB');
$m->query('ALTER TABLE b ADD CONSTRAINT b_fk FOREIGN KEY (a_id) REFERENCES a (id) ON DELETE CASCADE');
// -> SQLite error: near "CONSTRAINT": syntax error
```

**Suspected cause:** SQLite's `ALTER TABLE` grammar has no `ADD CONSTRAINT`
form (foreign keys can only be declared inside `CREATE TABLE`), and litewire's
MySQL→SQLite statement translation (the `litewire` git dependency pinned in the
workspace `Cargo.toml`, used by `crates/ephpm-server/src/lib.rs` for the
`[db.sqlite.proxy]` MySQL frontend) passes the `ALTER TABLE … ADD CONSTRAINT`
through untouched. A translation that recognises the `ADD CONSTRAINT … FOREIGN
KEY` clause and turns it into a no-op (foreign keys are not enforced by default
in SQLite anyway, so dropping the constraint keeps the data model consistent
with what MySQL-targeted apps get on `PRAGMA foreign_keys = OFF`) — or a
table-rebuild — would unblock every CodeIgniter/Laravel-style migration that
adds foreign keys in a second step, which is the common pattern.

**Status in the recipe:** only `compose.yml` (MariaDB) is shipped; the README
says the embedded variant is not available and points here.
