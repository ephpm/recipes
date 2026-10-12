# ProjectSend on ePHPm

| | |
|---|---|
| App | [ProjectSend](https://www.projectsend.org) 2.7.0 (`PROJECTSEND_VERSION` build arg), a Laravel + Inertia app |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm, plus queue worker and scheduler containers |
| Default stack | `compose.yml`: ePHPm + `worker` (queue) + `scheduler` sidecars (same image) + MySQL 8.4 |
| Single container | not offered (not tried on the embedded database) |
| Status | tested 2026-10-12 on v0.11.3-php8.5: image build, migrations on start, first administrator created from the environment, log in through the JSON login endpoint, authenticated dashboard answers 200, `artisan migrate:status` |

## Notes

* The release zip ships `vendor/` and built assets, so there is no Composer
  or Node stage.
* The first administrator is created by the entrypoint from
  `PROJECTSEND_ADMIN_EMAIL` / `PROJECTSEND_ADMIN_PASSWORD` (defaults in
  `compose.yml` are for trying it out: change them). Without them the browser
  shows the setup screen.
* `APP_KEY` is generated once into the `storage` volume; set `APP_KEY` to pin one.
* `APP_URL` must be the address users open it at.
* Sessions, cache and queue use the database driver, so no Redis is needed.
* The CSRF cookie is named `laravel_xsrf` (not `XSRF-TOKEN`); scripted
  clients echo it (URL-decoded) in `X-XSRF-TOKEN`, as `test.sh` does.
* Uploaded files are served through PHP (`PROJECTSEND_FILE_DELIVERY=php`).
