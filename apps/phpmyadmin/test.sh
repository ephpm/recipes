#!/usr/bin/env bash
# Smoke test: log in to the MariaDB through phpMyAdmin's cookie-auth form,
# create a database from the "Databases" page, see it listed, and confirm it
# exists on the server. Single compose variant.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28306
recipe_init phpmyadmin

compose_up
wait_http "$BASE/" 200 180
# the base image's E2E fixtures (issues/joomla.md) must not be served
fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
expect_body "$BASE/" 'name="pma_username"'

# 1. real workflow: log in to the db as root (cookie auth: form + session token)
jar="$(cookie_jar)"
token="$(form_value "$BASE/index.php?route=/" token -c "$jar" -b "$jar")"
[ -n "$token" ] || { echo "!!! no token on the login page" >&2; exit 1; }
expect_status "$BASE/index.php?route=/" 302 -c "$jar" -b "$jar" \
    --data-urlencode "token=$token" --data "pma_username=root&pma_password=root&server=1&route=%2F"
expect_body "$BASE/index.php?route=/" 'Server version' -b "$jar"     # the server-info home page
grep -q 'pmaAuth-1' "$jar" || { echo "!!! no pmaAuth-1 cookie after login" >&2; exit 1; }

# 2. create a database from the Databases page …
token="$(form_value "$BASE/index.php?route=/server/databases" token -c "$jar" -b "$jar")"
[ -n "$token" ] || { echo "!!! no token on the databases page" >&2; exit 1; }
expect_body "$BASE/index.php?route=/server/databases/create" '"success":true' -c "$jar" -b "$jar" \
    --data-urlencode "token=$token" --data "new_db=ephpm_recipe&db_collation=utf8mb4_general_ci&ajax_request=true&server=1"
expect_body "$BASE/index.php?route=/server/databases" 'ephpm_recipe' -b "$jar"

# 3. … and it really exists on the MariaDB
run_in db mariadb -uroot -proot -e 'SHOW DATABASES' | grep '^ephpm_recipe$' >/dev/null \
    || { echo "!!! database not found on the server" >&2; exit 1; }
echo "==> database ephpm_recipe exists on the server"

# 4. the session lives in ePHPm's KV store (session.save_handler = ephpm)
run_in ephpm ephpm kv keys 'session:*' | grep 'session:' >/dev/null \
    || { echo "!!! no PHP session in the KV store" >&2; exit 1; }
echo "==> PHP session stored in the KV store"

# 5. PHP-only directories are not served
expect_status "$BASE/libraries/vendor_config.php" 403
expect_status "$BASE/config.sample.inc.php" 403
rm -f "$jar"
