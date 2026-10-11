# BookStack: embedded database variant not shipped

**Recipe:** `apps/bookstack` — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.5` — **Date:** 2026-10-11

## What was tried

`compose.embedded.yml` with `[db.sqlite] path = ...` + `[db.sqlite.proxy]
mysql_listen = "127.0.0.1:3306"`, BookStack configured with
`DB_HOST=127.0.0.1 DB_USERNAME=root DB_PASSWORD=""`, and the entrypoint
running `ephpm php artisan migrate --force` (BookStack v26.09.1, Laravel 12)
against the embedded MySQL-compatible listener.

## What happened

The first nine migrations run (`create_users_table`, `create_books_table`,
… — plain `CREATE TABLE` / `INSERT`), then
`2015_08_29_105422_add_roles_and_permissions` fails:

```
SQLSTATE[HY000]: General error: 1105 SQLite error: near "CONSTRAINT": syntax error
(Connection: mysql, Host: 127.0.0.1, Port: 3306, Database: bookstack,
 SQL: alter table `role_user` add constraint `role_user_user_id_foreign`
      foreign key (`user_id`) references `users` (`id`)
      on delete cascade on update cascade)
```

Every later request answers 500 (schema half-applied).

## Suspected cause

litewire's MySQL→SQLite translation forwards `ALTER TABLE … ADD CONSTRAINT …
FOREIGN KEY …` verbatim, and SQLite (and the Turso engine) has no `ALTER TABLE
ADD CONSTRAINT` at all — foreign keys can only be declared inside `CREATE
TABLE`. Laravel's MySQL grammar emits the constraint as a separate `ALTER`
after the table exists (`$table->foreign(...)` in a migration), so any Laravel
app whose migrations add foreign keys this way — which is most of them,
BookStack has dozens — cannot migrate on the embedded database. A translation
would have to either rewrite the table (`CREATE TABLE new … ; INSERT … ;
DROP; RENAME`, the SQLite recipe) or accept and ignore the constraint (losing
referential actions such as `ON DELETE CASCADE`, which BookStack relies on
for cleanup).

Not reproducible with a one-liner against a stock ePHPm without the app, but
the statement above is self-contained: any `ALTER TABLE t ADD CONSTRAINT c
FOREIGN KEY (col) REFERENCES u (id)` sent to `[db.sqlite.proxy] mysql_listen`
reproduces it.

## Outcome

Only `compose.yml` (MariaDB) is shipped for BookStack. The README says the
embedded variant is not offered and why.
