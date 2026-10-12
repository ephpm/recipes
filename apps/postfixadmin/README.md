# PostfixAdmin 4.0.5 on ePHPm

| | |
|---|---|
| App | PostfixAdmin 4.0.5 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache/nginx + php-fpm in front of PostfixAdmin |
| Default stack | `compose.yml`: ePHPm + MariaDB 11 (Postfix/Dovecot are yours) |
| Single container | no (not tried) |
| Status | tested 2026-10-12 on v0.11.3-php8.5: config.local.php written from the environment, schema created on start, first superadmin created, log in through the form, add a domain in the admin UI and list it, `postfixadmin-cli.php` on the embedded PHP |

## Notes

* `POSTFIXADMIN_SETUP_PASSWORD` is required (hashed into `config.local.php`); `POSTFIXADMIN_ADMIN_PASSWORD` creates the first superadmin (`POSTFIXADMIN_ADMIN_EMAIL`).
* **`emailcheck_resolve_domain` is off.** PostfixAdmin's DNS check of the domain part of every address calls `checkdnsrr()`, which hangs on ePHPm (known `dns_get_record()` limit): with it on, adding a domain or admin never answers. The first superadmin is inserted with SQL for the same reason.
* Use `php scripts/postfixadmin-cli.php ...` (`scripts/postfixadmin-cli` is a shell wrapper that does not suit this image).
* Config edits need a restart (OPcache timestamp validation is off in ePHPm serve mode); the entrypoint rewrites `config.local.php` on every start.
