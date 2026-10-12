# ePHPm issues found while writing the phpIPAM recipe

Found on `ephpm/ephpm:v0.11.3-php8.5`, 2026-10-12.

## The `sockets` PHP extension is not built into the SDK

**Severity: blocks phpIPAM.** `ephpm php -m` has no `sockets`. phpIPAM's
`functions/checks/check_php_build.php` lists `sockets` in `$requiredExt` and
renders a "phpIPAM requirements error" page for every authenticated page when
it is missing (login itself works; the app is unusable after it). It also
wants `PEAR.php` on the include path, which is a userland package and not an
ePHPm problem. Other apps that use `socket_*()` (ping/scan tools, some mail
and monitoring software) are affected the same way. Add `sockets` to the
php-sdk's extension list, or document it as unsupported next to the other
missing extensions (ldap, imagick, imap, memcached, tidy, gnupg).
