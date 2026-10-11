# Akaunting: two ePHPm findings

**Recipe:** `apps/akaunting` — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.3` and `-php8.5` — **Date:** 2026-10-11

## 1. `checkdnsrr()` / `dns_get_record()` hang forever (`gethostbyname()` works)

### What happened

`POST /api/contacts` with an `email` never answers (curl gives up after
150 s; no PHP error, nothing in `laravel.log`). The same request without an
email completes in well under a second. Akaunting validates contact emails
with Laravel's `email:rfc,dns` rule, whose `dns` check calls
`checkdnsrr($domain, 'MX')` / `'A'`.

### Minimal repro (pristine image, no app)

```
$ for fn in 'checkdnsrr("example.com","MX")' 'dns_get_record("example.com", DNS_A)' 'gethostbyname("example.com")'; do
    podman run --rm --entrypoint sh docker.io/ephpm/ephpm:v0.11.3-php8.5 -c \
      "timeout 12 ephpm php -r 'var_dump(@$fn);' || echo HANG"; done
HANG                                   # checkdnsrr
HANG                                   # dns_get_record
string(13) "104.20.23.154"             # gethostbyname — instant
```

`/etc/resolv.conf` in the container is the usual podman one
(`nameserver 169.254.1.1`, `10.255.255.254`); `gethostbyname()` /
`gethostbynamel()` resolve through it immediately. Only the libresolv-based
functions (`checkdnsrr`, `dns_get_record`, `dns_get_mx`, which use
`res_nsearch`/`res_nquery` from `ext/standard/dns.c`) block, and they never
time out.

### Suspected cause

The php-sdk's `libphp.a` is linked against a resolver that is not the
container's glibc one (static-php-cli builds against its own libraries;
glibc's `res_*` need `libresolv` and read `/etc/resolv.conf` through the
same NSS/resolver state as `getaddrinfo`). Either the `res_*` symbols come
from a bundled implementation that never reads `resolv.conf` and retries
indefinitely, or they are called without `res_ninit` succeeding under ZTS
(each PHP thread has its own `__res_state`). Worth checking `nm` on
`libphp.a` for `res_nsearch`/`__res_state` and whether `-lresolv` is on the
link line.

### Impact

Every Laravel app using `email:dns` (Akaunting contacts, many others), every
`checkdnsrr()`-based SPF/MX check (mailers, contact forms), and
`dns_get_record()` users hang a PHP worker thread until `[server.timeouts]
request` fires. The recipe's test creates the customer **without** an email
and the README documents the limitation.

## 2. Laravel's scheduler cannot find `php` in the image (PHP_BINARY is `ephpm`)

### What happened

`ephpm php artisan schedule:run` with a scheduled command due:

```
  2026-10-11 21:07:28 Running ['artisan' firewall:unblockip] ........ 5ms FAIL
  ⇂ 'php' 'artisan' firewall:unblockip > '/dev/null' 2>&1
```

Laravel runs `Schedule::command()` entries as a **child process** built from
`Application::phpBinary()` (Symfony's `PhpExecutableFinder`). Under
`ephpm php`, `PHP_BINARY` is `/usr/local/bin/ephpm`, which the finder rejects
(running it without the `php` subcommand is not a PHP CLI), so it falls back
to the bare name `php` — and the image ships no `php`. Every due
`->command()` job fails; `->call()`/`->job()` entries (in-process) work,
which is why `schedule:run` looked fine on the other recipes' first run.
The same applies to anything that re-invokes PHP (`queue:work` restarts,
PHPUnit process isolation, Composer scripts).

### Minimal repro

```
podman run --rm --entrypoint sh docker.io/ephpm/ephpm:v0.11.3-php8.5 -c \
  'ephpm php -r "echo PHP_BINARY, PHP_EOL;"; which php || echo "no php on PATH"'
/usr/local/bin/ephpm
no php on PATH
```

### Fix used in the recipes

Every Laravel recipe's Dockerfile adds a shim:

```dockerfile
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php
```

### Suggested fix in ePHPm

Ship that shim in the `ephpm/ephpm` image (the CLI docs already tell users
to "point such tools at a wrapper script that execs `ephpm php`"), or make
`ephpm` behave as the PHP CLI when invoked as `php` (multi-call binary) so a
symlink suffices.
