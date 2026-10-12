# XBackBone 3.8.2 on ePHPm

| | |
|---|---|
| App | XBackBone 3.8.2 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache/nginx + php-fpm |
| Default stack | `compose.yml`: ePHPm alone (SQLite database inside a volume) |
| Single container | yes (native SQLite) |
| Status | tested 2026-10-12 on v0.11.3-php8.5: unattended install on first start, log in as admin, issue an upload token, upload a file through the upload API and read it back from its raw URL |

## Notes

* The web installer (a POST to `/install/`) is run once on a private loopback port from `XBACKBONE_ADMIN_PASSWORD` / `XBACKBONE_ADMIN_EMAIL` / `XBACKBONE_BASE_URL`. `XBACKBONE_BASE_URL` must be the address users open it at.
* `config.php` is kept in the storage volume (symlinked into place); the SQLite file is in the `database` volume.
* Use `/install/` with the trailing slash if you run the installer by hand: `/install` falls through to the Slim router and answers 500.
* Uploads need a user token (profile page, or `POST /user/1/refreshToken` while logged in).
