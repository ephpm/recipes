# ePHPm issues found while writing the FreshRSS recipe

Found on `ephpm/ephpm:v0.11.3-php8.5` (Linux x86_64), 2026-10-11.

## 1. `dns_get_record()` / `checkdnsrr()` never return — `__res_nsearch` tail-calls itself

**Severity: high.** Any PHP code that calls `dns_get_record()` or `checkdnsrr()`
spins at 100 % CPU forever. `max_execution_time` does not interrupt it (the loop
is inside a C call, never at a VM checkpoint), so under `ephpm serve` the PHP
pool thread is lost for the life of the process; after `[php] concurrency`
such requests the server stops executing PHP.

FreshRSS calls `dns_get_record()` on every feed add (SSRF protection,
`app/Utils/httpUtil.php::checkUrl`) and on every feed fetch
(`getRetryAfterFile` → `Minz_Request::serverIsPublic`), so without a
workaround the application cannot add or refresh a single feed. Other apps that
hit it: anything using Symfony's `Email` address DNS validation, WordPress'
`wp_mail` SPF plugins, Laravel's `dns` validation rule, PHPMailer host checks.

### Minimal repro (stock image, no application)

```bash
podman run --rm --entrypoint sh docker.io/ephpm/ephpm:v0.11.3-php8.5 -c '
  timeout 15 ephpm php -r "var_dump(gethostbyname(\"github.com\"));"; echo "rc=$?"      # 140.82.114.3, rc=0
  timeout 15 ephpm php -r "var_dump(dns_get_record(\"github.com\", DNS_A));"; echo "rc=$?" # (no output) rc=124
  timeout 15 ephpm php -r "var_dump(checkdnsrr(\"github.com\", \"A\"));"; echo "rc=$?"     # rc=124
  timeout 15 ephpm php -r "var_dump(dns_get_record(\"127.0.0.1\", DNS_A));"; echo "rc=$?"  # rc=124 — even an IP literal
'
```

`gethostbyname()` (getaddrinfo through the dynamic glibc) works; the resolver
entry points PHP's `ext/standard/dns.c` uses do not.

### Where it spins

gdb attached to the hung process (`--cap-add SYS_PTRACE`, `apt-get install gdb`
in a throwaway container):

```
#0  0x0000567809018a70 in __res_nsearch ()        <-- inside the ephpm image itself, not libc.so.6
#1  0x0000567807d7e524 in zif_dns_get_record ()
#2  0x0000567807bb0df7 in execute_ex ()
#3  0x0000567807bb6246 in zend_execute ()
...
#7  0x000056780901830d in ephpm_cli_main ()
```

Frame 0 is `__res_nsearch` at an address inside the `ephpm` binary (`ldd` shows
only the dynamic `libc.so.6`), and it never leaves that frame: `utime` grows by
100 ticks/s with `State: R`.

### Suspected cause (verify before acting)

`crates/ephpm-php/resolver_shim.c` provides the underscored names PHP's
`dns.c` references as "thin wrappers over the still-exported public entry
points":

```c
#include <resolv.h>
int __res_nsearch(res_state statp, const char *dname, int class, int type,
                  unsigned char *answer, int anslen) {
    return res_nsearch(statp, dname, class, type, answer, anslen);
}
```

On glibc **older than 2.34**, `<resolv.h>` itself defines
`#define res_nsearch __res_nsearch` (and `dn_expand` → `__dn_expand`,
`dn_skipname` → `__dn_skipname`). Compiled against such a header the wrapper
becomes `__res_nsearch(...) { return __res_nsearch(...); }` — a self tail-call
the compiler turns into a jump, i.e. exactly the single-frame 100 % CPU spin
above. `build.rs` says the Linux release is built against a glibc-2.28
(manylinux_2_28) floor, which is such a glibc. The same applies to
`__dn_expand` / `__dn_skipname`, which simply are not reached because
`__res_nsearch` never returns.

Suggested fix in the shim: after `#include <resolv.h>`, `#undef res_nsearch`,
`#undef dn_expand`, `#undef dn_skipname` (the public symbols exist in every
glibc the binary can run on), or declare the public functions explicitly with
`__asm__("res_nsearch")` names. Add a test that `dns_get_record("localhost",
DNS_A)` returns within a second, since nothing in CI calls the resolver today.

### Workaround used by the recipe

PHP ≥ 8.0 removes a function listed in `disable_functions` from the function
table, which makes it redefinable in userland. The recipe sets
`disable_functions = dns_get_record` and `auto_prepend_file =
/etc/ephpm/dns-polyfill.php` (server: `[php] ini_overrides`; CLI: `-d` flags in
the `php` shim) and the polyfill answers A lookups with `gethostbynamel()` and
AAAA lookups with `getent ahostsv6` — both go through getaddrinfo() and work.
Only A/AAAA are implemented (all FreshRSS needs). Remove the polyfill once the
shim is fixed.

## 2. (minor, doc) `sockets` is not compiled in

The recipe brief's extension list says `sockets` is built in; `ephpm php -m` on
`v0.11.3-php8.5` does not list it (`socket_addrinfo_lookup()` is undefined).
The site's `reference/cli/php.md` extension list also omits it, so this is only
a brief-vs-image mismatch, noted so nobody plans a workaround on `sockets`
(the first version of the polyfill above did).

## 3. Embedded database: column-level `CHARACTER SET` / `COLLATE` (same as issues/yourls.md)

`cli/do-install.php --db-type mysql --db-host 127.0.0.1:3306` succeeds
against ePHPm's embedded database, but `cli/create-user.php` then fails
("FreshRSS could not create user!"): the per-user tables in
`app/SQL/install.sql.mysql.php` declare `url VARCHAR(32768) CHARACTER SET
latin1 COLLATE latin1_bin`, `guid VARCHAR(767) CHARACTER SET latin1 COLLATE
latin1_bin`, …, and litewire forwards column-level charset/collation clauses
to Turso untranslated. Full repro and suggested fix in `issues/yourls.md`.
The recipe ships no embedded-database variant for FreshRSS.

## 4. (gap) no `PATH_INFO` — `script.php/extra/path` is not split

FreshRSS's Google Reader-compatible API lives at
`/api/greader.php/reader/api/0/...` and needs `PATH_INFO` (its nginx reference
config uses `fastcgi_split_path_info ^(.+\.php)(/.*)$`). ePHPm's
`Router::resolve_fallback` probes `$uri` as a literal file, finds nothing, and
rewrites to `/index.php`, so every greader URL lands on the wrong script. No
crate sets `PATH_INFO` at all (grep over `crates/` for `PATH_INFO`/`path_info`
is empty; the two mentions in `site/content` are generic tables). The Fever
API (`/api/fever.php?api`) is query-string based and works. Mobile clients that
speak only the Google Reader API (most of them) cannot be pointed at FreshRSS on
ePHPm until the router splits `<script>.php/<path-info>`.
