## shlink: `PHP_BINARY` under `ephpm php` breaks every tool that re-spawns PHP (Symfony `PhpExecutableFinder`)

**App:** Shlink 5.1.7, recipe `apps/shlink`. Not Shlink-specific — it is the
first app in this repo whose *install path* spawns PHP sub-processes.

**Symptom:** the official entrypoint's `vendor/bin/shlink-installer init`, and
Shlink's own `bin/cli db:create` / `db:migrate`, fail under `ephpm php`:

```
In Process.php line 293:
  The command "'/usr/local/bin/ephpm' 'bin/doctrine' 'orm:schema-tool:create' '--no-interaction'" failed.
  Exit Code: 2(Misuse of shell builtins)
  Error Output:
  error: unrecognized subcommand 'bin/doctrine'
  Usage: ephpm [COMMAND]
```

Each of those commands runs the next step as a child process through
`Symfony\Component\Process\PhpExecutableFinder::find()`, which returns
`PHP_BINARY` whenever `PHP_SAPI` is `cli`. Under `ephpm php`, `PHP_BINARY` is
`/usr/local/bin/ephpm` ([documented](https://ephpm.dev/reference/cli/php/#_server-the-environment-and-php_binary)),
so the child is `ephpm bin/doctrine …` — and `ephpm` has no such subcommand.
The documented advice ("point such tools at a wrapper script") does not help
here: the finder consults the constant, not `PATH`, and the app does not expose
a knob for the binary.

**Minimal repro:**

```bash
ephpm php -r 'echo PHP_BINARY, "\n"; passthru(PHP_BINARY . " -r \"echo 1;\"");'
# /usr/local/bin/ephpm
# error: unrecognized subcommand '-r'
```

**Who else hits it:** anything built on `symfony/process` + `PhpExecutableFinder`
— Composer plugins that run scripts, Laravel's `artisan serve`/queue workers
with `--isolated`, PHPUnit process isolation, Symfony's `server:dump`, Doctrine
migration wrappers, Deployer/`php artisan` from Envoy, …

**Suggested fix (ePHPm):** make the `ephpm` executable behave like a PHP CLI
when it is invoked the way `PHP_BINARY` is: if `argv[1]` is not a known
subcommand and is a PHP CLI option (`-r`, `-d`, `-f`, `--`…) or an existing
file, dispatch to `ephpm php` with the arguments unchanged. That keeps
`PHP_BINARY` truthful (the path *is* a working PHP CLI) without a wrapper.
Alternatively (weaker) let `ephpm php` export a `PHP_BINARY` that points at a
shipped `/usr/local/bin/php` shim in the Docker image.

**Workaround in the recipe:** `entrypoint.sh` runs the Doctrine steps the
commands would spawn (`bin/doctrine orm:schema-tool:create`,
`vendor/doctrine/migrations/bin/doctrine-migrations.php migrations:migrate`,
`orm:generate-proxies`, `orm:clear-cache:metadata`) with `ephpm php` directly.
`shlink db:create`, `db:migrate` and `shlink-installer` stay broken in the
container; the README says so.

## shlink (and every Doctrine app): Doctrine's MySQL DDL fails on the embedded database

**Apps:** Shlink 5.1.7 first; the same Doctrine ORM / DBAL "MySQL platform"
DDL is what wallabag, Kimai, Part-DB, Koillection, SolidInvoice, Sylius,
Thelia and UVdesk emit, so their `[db.sqlite]` single-container variants are
not shipped either (each README points here).

**Symptom:** `bin/doctrine orm:schema-tool:create` against
`[db.sqlite.proxy] mysql_listen` fails on the first statement:

```
SQLSTATE[HY000]: General error: 1105 SQLite error: near "SET": syntax error
```

`orm:schema-tool:create --dump-sql` shows what Doctrine sends when the
connection reports itself as MariaDB (the `DB_VERSION` / `serverVersion`
Doctrine is told):

```sql
CREATE TABLE domains (
  id BIGINT UNSIGNED AUTO_INCREMENT NOT NULL,
  authority VARCHAR(255) CHARACTER SET utf8mb4 NOT NULL COLLATE `utf8mb4_unicode_ci`,
  ...
  UNIQUE INDEX UNIQ_8C7BBF9D4AF96AFC (authority), PRIMARY KEY (id)
) DEFAULT CHARACTER SET utf8mb4;
ALTER TABLE short_urls ADD CONSTRAINT FK_4A53F934115F0EE5 FOREIGN KEY (domain_id) REFERENCES domains (id) ON DELETE RESTRICT;
```

Two constructs litewire's MySQL→SQLite translation does not handle:

1. a per-column `CHARACTER SET x … COLLATE y` clause inside `CREATE TABLE`
   (the `near "SET"` error — the table-level `DEFAULT CHARACTER SET` is
   apparently stripped, the column-level one is not), and
2. `ALTER TABLE … ADD CONSTRAINT … FOREIGN KEY` (see the easyappointments
   entry: SQLite has no such statement).

Also present in Doctrine's DDL and worth checking once those two are handled:
`UNIQUE INDEX name (cols)` / `INDEX name (cols)` inside `CREATE TABLE`,
`BIGINT UNSIGNED`, `TINYINT`, `JSON`, `VARBINARY(32)`, `DOUBLE PRECISION`,
and backtick-quoted reserved column names (`` `date` ``, `` `key` ``).

**Minimal repro:**

```php
$m = new mysqli('127.0.0.1', 'root', '', 'x', 3306);
$m->query('CREATE TABLE d (id BIGINT UNSIGNED AUTO_INCREMENT NOT NULL, a VARCHAR(255) CHARACTER SET utf8mb4 NOT NULL COLLATE `utf8mb4_unicode_ci`, PRIMARY KEY (id)) DEFAULT CHARACTER SET utf8mb4');
// -> SQLite error: near "SET": syntax error
```

**Suspected cause:** litewire's `CREATE TABLE` rewriter (git dependency pinned
in the workspace `Cargo.toml`) handles the table options but not the column
attribute list of the MySQL grammar; `CHARACTER SET`/`COLLATE` on a column
are no-ops for SQLite and can be dropped, which — together with ignoring
`ADD CONSTRAINT … FOREIGN KEY` — would make the whole Doctrine family
installable on the embedded engine.
