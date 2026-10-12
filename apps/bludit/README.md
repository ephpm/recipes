# Bludit 3.22.0 on ePHPm

| | |
|---|---|
| App | Bludit 3.22.0 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php / nginx + php-fpm |
| Default stack | `compose.yml`: ePHPm alone (flat files, no database) |
| Single container | yes (native) |
| Status | tested 2026-10-12 on v0.11.3-php8.5: unattended install on first start, log in to /admin, create a page through the admin form and read it on the public site, database files refused (403) |

## Notes

* Flat-file CMS: the `bl-content` volume holds everything (pages, users, uploads).
* Set `BLUDIT_ADMIN_PASSWORD` for the first start; the entrypoint runs Bludit's web installer once on a private loopback port. Without it, open the site to run the installer yourself.
* The `.htaccess` rewrite is `[server] fallback` in `ephpm.toml`; `bl-content/databases` is in `blocked_paths`.
