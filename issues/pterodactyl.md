# Laravel's scheduler runs `ephpm artisan ...` (silently) — the `php` shim does not cover it

**Recipe:** `apps/pterodactyl` (same mechanism in `apps/freescout`) — **ePHPm:**
`ephpm/ephpm:v0.11.3-php8.5` — **Date:** 2026-10-11

This is a consequence of ephpm#558 (`PHP_BINARY` is `ephpm` under
`ephpm php`), recorded because the workaround the recipes use for #558 —
a `/usr/local/bin/php` → `exec ephpm php "$@"` shim — does **not** fix it.

## Symptom

`artisan schedule:run` in a Laravel 12 app (Pterodactyl 1.15) prints

```
Running ['artisan' p:schedule:process] .... 19.68ms DONE
```

but the command never ran. Laravel builds each scheduled command as
`Application::phpBinary() . ' artisan ...'`; `phpBinary()` is
`php_binary()` → Symfony `PhpExecutableFinder::find()`, which returns the
`PHP_BINARY` **constant** when `PHP_SAPI` is `cli` — `/usr/local/bin/ephpm`.
The shell then runs `'/usr/local/bin/ephpm' 'artisan' p:schedule:process`,
which exits 2 (`error: unrecognized subcommand 'artisan'`); Laravel 12's
`schedule:run` reports `DONE` regardless (the task callback's return value,
not the exit code). FreeScout (Laravel 5.5) logs
`Running scheduled command: '/usr/local/bin/ephpm' 'artisan' freescout:fetch-emails ...`
— mail is never fetched.

## Minimal repro

```bash
cd /app   # any Laravel app on ePHPm
ephpm php -r 'require "vendor/autoload.php"; echo Illuminate\Console\Application::phpBinary(), "\n";'
# '/usr/local/bin/ephpm'
/usr/local/bin/ephpm artisan --version; echo $?
# error: unrecognized subcommand 'artisan' / 2
```

## Workarounds

* **Symfony Process ≥ 4.x (Laravel 6+):** `PhpExecutableFinder` checks the
  `PHP_BINARY` *environment variable* before the constant. `ENV
  PHP_BINARY=/usr/local/bin/php` (the shim) in the image fixes the scheduler
  and anything else that uses the finder (`apps/pterodactyl`).
* **Older Symfony (FreeScout's 3.x)** ignores the variable outside HHVM;
  `apps/freescout` patches the app's own `Console\Application::phpBinary()`.

Other recipes with a Laravel scheduler sidecar that only ship the `php` shim
(e.g. `pelican`, `bookstack`, `laravel`, `koel`, `firefly-iii` — not checked
individually here) are likely running no scheduled commands at all while
their logs look healthy.

**Follow-up (2026-10-11):** checked per recipe by evaluating
`Illuminate\Console\Application::phpBinary()` in each built image with and
without the variable. Without it, `phpBinary()` was `'/usr/local/bin/ephpm'`
— so every `$schedule->command(...)` failed silently — in `bagisto`,
`cachet`, `invoiceninja`, `krayin`, `laravel`, `linkace`, `pelican`,
`snipe-it` and `speedtest-tracker` (on PHP 8.5). `akaunting` (on the
php8.3 image) got `'php'`, which the shim on PATH already served. All of
them, plus the blocked `koel` and `monica`, now set
`ENV PHP_BINARY=/usr/local/bin/php` (the `laravel` recipe also gained the
`php` shim), and each smoke test runs `<phpBinary()> artisan --version` the
way the scheduler does and fails if it does not work. `bookstack`,
`firefly-iii`, `heimdall` and `flarum` run no Laravel scheduler (Firefly's
cron sidecar calls its HTTP cron endpoint), so they were left alone.

## Suspected fix in ePHPm

`ephpm php` could set `PHP_BINARY` to something that re-enters the CLI —
e.g. a tiny `ephpm-php` multi-call alias (argv[0] dispatch) shipped next to
`ephpm`, or honour `ephpm <script.php>` / `ephpm artisan` as `ephpm php ...`
when the first argument is an existing file. Either makes every
`PHP_BINARY`-based re-spawn (Laravel scheduler, `queue:listen`, Composer,
PHPUnit process isolation) work without per-app shims.
