#!/usr/bin/env bash
# Smoke test: unattended install, log in to /admin, create a page through the
# admin form, read it on the public site, check private paths are refused.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28170
recipe_init bludit
export BLUDIT_ADMIN_PASSWORD="Recipe-pass-1234"
compose_up
wait_http "$BASE/" 200 120
jar="$(cookie_jar)"
tok="$(form_value "$BASE/admin/" tokenCSRF -c "$jar" -b "$jar")"
[ -n "$tok" ] || { echo "!!! no tokenCSRF on the login form" >&2; exit 1; }
curl -s -o /dev/null --max-time 30 -c "$jar" -b "$jar" --data-urlencode "tokenCSRF=$tok" \
    --data "username=admin&password=$BLUDIT_ADMIN_PASSWORD&save=" "$BASE/admin/"
expect_body "$BASE/admin/dashboard" "Dashboard" -c "$jar" -b "$jar"
tok="$(form_value "$BASE/admin/new-content" tokenCSRF -c "$jar" -b "$jar")"
curl -s -o /dev/null --max-time 30 -c "$jar" -b "$jar" --data-urlencode "tokenCSRF=$tok" \
    --data "uuid=recipe-uuid-1&type=published&title=Hello+from+ePHPm&content=Created+by+the+recipe+smoke+test&slug=hello-from-ephpm&position=1" \
    "$BASE/admin/new-content"
expect_body "$BASE/hello-from-ephpm" "Created by the recipe smoke test"
expect_status "$BASE/bl-content/databases/users.php" 403
expect_status "$BASE/bl-content/databases/site.php" 403
rm -f "$jar"
