# Laravel's scheduler cannot find `php` in the ePHPm image (PHP_BINARY is `ephpm`)

**Recipes:** every Laravel app with a scheduler sidecar (`apps/akaunting`,
`apps/linkace`, `apps/snipe-it`, `apps/monica`, `apps/invoiceninja`,
`apps/koel`) — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.5` / `-php8.3` —
**Date:** 2026-10-11

## What happened

`ephpm php artisan schedule:run` inside the Akaunting container, with a
scheduled command due:

```
  2026-10-11 21:07:28 Running ['artisan' firewall:unblockip] ........ 5ms FAIL
  ⇂ 'php' 'artisan' firewall:unblockip > '/dev/null' 2>&1
```

Laravel's scheduler runs `Schedule::command()` entries as a **child
process**: `Illuminate\Console\Scheduling\Event` builds the command line
from `Application::phpBinary()`, which uses Symfony's `PhpExecutableFinder`.
Under `ephpm php`, `PHP_BINARY` is `/usr/local/bin/ephpm` (documented in
`reference/cli/php.md`), which the finder rejects as a PHP executable
(running it without the `php` subcommand is not a PHP CLI), so it falls
back to the bare name `php` — and the image ships no `php`. Every due
`->command()` job fails; `->call()` and `->job()` entries (in-process) work,
which is why `schedule:run` looked fine on the other recipes' first run (no
command was due yet). The same applies to anything else that re-invokes
PHP (`artisan queue:work` restarts, PHPUnit process isolation, Composer
scripts).

## Minimal repro

```
podman run --rm --entrypoint sh docker.io/ephpm/ephpm:v0.11.3-php8.5 -c \
  'ephpm php -r "echo PHP_BINARY, PHP_EOL;"; which php || echo "no php on PATH"'
/usr/local/bin/ephpm
no php on PATH
```

## Fix used in the recipes

Every Laravel recipe's Dockerfile adds a two-line shim:

```dockerfile
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php
```

With it, `php artisan ...` child processes run on the embedded PHP.

## Suggested fix in ePHPm

Ship that shim in the `ephpm/ephpm` image (and in the package installers):
the CLI docs already tell users to "point such tools at a wrapper script
that execs `ephpm php`", and the Docker image is the one place where that
can be done once for everybody. Alternatively, teach `ephpm` to behave as
the PHP CLI when `argv[0]` is `php` (busybox-style multi-call), so a
symlink suffices.
