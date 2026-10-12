# phpIPAM on ePHPm

| | |
|---|---|
| App | phpIPAM 1.8.3 (`PHPIPAM_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (or nginx + php-fpm) + cron |
| Default stack | `compose.yml`: ePHPm + MariaDB 11 |
| Status | **blocked** (checked 2026-10-12 on v0.11.3-php8.5): the image builds, the schema imports and Admin can log in, but every page after login is replaced by phpIPAM's "required PHP extensions are missing" error: ePHPm has no `sockets` extension (see `issues/phpipam.md`). `test.sh` stops at that check. |

The recipe (config written from the environment, schema imported on first
start, Admin password set) is complete and will be re-tested once ePHPm ships
`sockets`. Note that phpIPAM builds redirects from the server port, so it
must be published on the container port (8080) or sit behind a proxy.
