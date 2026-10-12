# FOSSBilling on ePHPm

| | |
|---|---|
| App | FOSSBilling 0.8.8 (`FOSSBILLING_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache/nginx + php-fpm + the cron entry |
| Default stack | `compose.yml`: ePHPm + MariaDB 11 |
| Status | **blocked** (checked 2026-10-12 on v0.11.3-php8.5): the unattended install completes, but every page then answers 500: symfony/intl cannot read its `.php.gz` data because ePHPm's zlib file streams return nothing (`issues/fossbilling.md`). |

The entrypoint (config in the data volume, installer driven by one POST to
`install/install.php?a=install`) and `ephpm.toml` (the `.htaccess` rewrite as
`fallback = [..., "/index.php?_url=$uri&$query_string"]`) are in place and
will be re-tested once zlib streams work. `test.sh` currently only waits for
the home page.
