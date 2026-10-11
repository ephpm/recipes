#!/usr/bin/env bash
# Smoke test: log in to the MariaDB through Adminer's login form, create a
# database from the "Create database" form, see it listed, confirm it exists
# on the server, and check a plugin + design load. Single compose variant.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28307
recipe_init adminer

# Exercise the official image's knobs too.
export ADMINER_DESIGN=hever ADMINER_PLUGINS="tables-filter"
compose_up
wait_http "$BASE/" 200 180
expect_body "$BASE/" 'name="auth\[username\]"'
expect_body "$BASE/" "auth\[server\]. value=.db."     # ADMINER_DEFAULT_SERVER prefilled

# 1. real workflow: log in to the db as root (the form posts auth[…] + the session token)
jar="$(cookie_jar)"
token="$(form_value "$BASE/" token -c "$jar" -b "$jar" || true)"
expect_status "$BASE/" 302 -c "$jar" -b "$jar" \
    --data-urlencode "token=$token" \
    --data "auth%5Bdriver%5D=server&auth%5Bserver%5D=db&auth%5Busername%5D=root&auth%5Bpassword%5D=root&auth%5Bdb%5D="
expect_body "$BASE/?server=db&username=root" 'Create database' -b "$jar"

# 2. create a database …
token="$(form_value "$BASE/?server=db&username=root&database=" token -c "$jar" -b "$jar")"
[ -n "$token" ] || { echo "!!! no token on the create-database form" >&2; exit 1; }
expect_status "$BASE/?server=db&username=root&database=" 302 -c "$jar" -b "$jar" \
    --data-urlencode "token=$token" --data "name=ephpm_recipe&collation="
expect_body "$BASE/?server=db&username=root" 'ephpm_recipe' -b "$jar"

# 3. … and it really exists on the MariaDB
run_in db mariadb -uroot -proot -e 'SHOW DATABASES' | grep '^ephpm_recipe$' >/dev/null \
    || { echo "!!! database not found on the server" >&2; exit 1; }
echo "==> database ephpm_recipe exists on the server"

# 4. the design CSS is served and the plugin stub was generated
expect_status "$BASE/adminer.css" 200
run_in ephpm sh -c 'grep -q "TablesFilter" plugins-enabled/001-tables-filter.php' \
    || { echo "!!! plugin stub missing" >&2; exit 1; }
echo "==> ADMINER_DESIGN and ADMINER_PLUGINS applied"

# 5. the session lives in ePHPm's KV store (session.save_handler = ephpm)
run_in ephpm ephpm kv keys 'session:*' | grep 'session:' >/dev/null \
    || { echo "!!! no PHP session in the KV store" >&2; exit 1; }
echo "==> PHP session stored in the KV store"

# 6. PHP sources are not served directly
expect_status "$BASE/adminer.php" 403
expect_status "$BASE/plugins/tables-filter.php" 403
rm -f "$jar"
