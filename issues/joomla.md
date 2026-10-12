# Published `ephpm/ephpm:v0.11.3-php8.5` is the E2E stage: test fixtures (phpinfo) and the test config ship in the image

**Found with:** `apps/joomla` (affects every recipe whose web root is
`/var/www/html`) — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.5` (image created
2026-10-11 02:21 UTC, revision label `45f284c`) — **Date:** 2026-10-11

## Symptom

The Joomla entrypoint copies the release into `/var/www/html` only when that
directory has no `index.php`, as the official image does. On the ePHPm base
image it never copied anything: `/var/www/html` already holds ~50 files —
ePHPm's own E2E fixtures (`info.php`, `shell_test.php`, `server_vars.php`,
`memory_hog.php`, `db_bridge_test.php`, `index.php`, ...). Any recipe that
`COPY`s its app *onto* `/var/www/html` (rather than replacing the directory)
serves them next to the app:

```
$ curl -s -o /dev/null -w '%{http_code} %{size_download}\n' http://127.0.0.1:28606/info.php
200 87946          # phpinfo(): every environment variable, DB passwords included
$ curl -s http://127.0.0.1:28606/shell_test.php
{"success":true,"output":"hello","error":""}
```

The default config is the test one too: `/etc/ephpm/ephpm.toml` is
`tests/ephpm-test.toml` (`sites_dir = "/var/www/sites"`, `max_body_size =
1024`, a `trusted_hosts` list of test hostnames, ...), so `docker run
ephpm/ephpm:v0.11.3-php8.5` with a mounted site and no config of its own runs
with test settings.

## Minimal repro

```bash
podman run --rm --entrypoint ls docker.io/ephpm/ephpm:v0.11.3-php8.5 /var/www/html | head
podman history --no-trunc --format '{{.CreatedBy}}' docker.io/ephpm/ephpm:v0.11.3-php8.5 | head -6
#   COPY tests/ephpm-test.toml /etc/ephpm/ephpm.toml # buildkit
#   COPY tests/docroot/ /var/www/html/ # buildkit
```

## Suspected cause

The source is already fixed: `docker/Dockerfile` splits `e2e` (fixtures, not
published) from `runtime` (the last stage, `docker/default/` placeholder +
production config), PR #549, which is in v0.11.0+, and
`.github/workflows/release.yml` builds with `--target runtime`. But the
layers above are exactly the `e2e` stage's, so the target is not being
honoured at publish time. The release job forces `DOCKER_BUILDKIT=0` so the
CLI posts to `POST /build`, which ephemerd's embedded BuildKit solver serves
— suspect that endpoint ignores the `target` query parameter (or resolves the
stage wrongly). xtask's `published_docker_image_has_no_test_fixtures` test
evidently checks the Dockerfile, not the pushed image; a post-push check of
the actual image (`docker run --rm <tag> ls /var/www/html`) would catch it.

## Workaround in the recipes

Every recipe whose web root is `/var/www/html` runs `RUN rm -rf
/var/www/html` before copying the app in, and its smoke test asserts that
`/info.php` does not answer with phpinfo(): `joomla`, `phpbb`, `roundcube`,
`librespeed`, `limesurvey`, and (2026-10-11, all re-tested) `adminer`,
`dokuwiki`, `easyappointments`, `espocrm`, `grav`, `invoiceplane`, `matomo`,
`mediawiki`, `nextcloud`, `ojs`, `phpmyadmin`, `wallos`, `wordpress`,
`yourls` — every one of those served `/info.php`, `/shell_test.php`,
`/uploads/shell.php` etc. before (their `fallback` starts with `$uri`, so an
existing file wins). Recipes whose document root is a *subdirectory* of
`/var/www/html` (`grocy`, `part-db`, `mautic`: `.../public`, `.../docroot`)
do not serve the fixtures, but the files still sit in the image next to the
app (`/var/www/html/vendor/secret.php` merges into the app's `vendor/`);
other recipes use `/app`, `/opt/...` or `/var/www/<app>` and are unaffected.

None of the recipes rely on the image's default `/etc/ephpm/ephpm.toml`
(the test config): every Dockerfile copies its own over it, and the
`EPHPM_CONFIG` variants point at their own files.
