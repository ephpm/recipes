#!/usr/bin/env bash
# Smoke test: first-start unattended install, log in as the configured
# administrator, report an issue through the web form and read it back,
# and run MantisBT's CLI through the embedded PHP.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28140
recipe_init mantisbt
export MANTIS_ADMIN_PASSWORD="Recipe-test-pass-1"

compose_up
wait_http "$BASE/login_page.php" 200 300
expect_status "$BASE/" 302

jar="$(cookie_jar)"
LT="$(form_value "$BASE/login_page.php" login_token -b "$jar" -c "$jar")"
curl -s -o /dev/null --max-time 60 -c "$jar" -b "$jar" --data-urlencode "login_token=$LT" \
    --data-urlencode "username=administrator" --data-urlencode "password=$MANTIS_ADMIN_PASSWORD" \
    "$BASE/login.php"
expect_body "$BASE/my_view_page.php" "Logout" -b "$jar" -c "$jar"

# a project must exist before an issue can be reported
ptok="$(form_value "$BASE/manage_proj_create_page.php" manage_proj_create_token -b "$jar" -c "$jar")"
curl -s -o /dev/null --max-time 60 -b "$jar" -c "$jar" --data-urlencode "manage_proj_create_token=$ptok" \
    --data "name=Recipe&status=10&view_state=10&description=smoke" "$BASE/manage_proj_create.php"
curl -s -o /dev/null -b "$jar" -c "$jar" "$BASE/set_project.php?project_id=1"
ctok="$(form_value "$BASE/manage_proj_edit_page.php?project_id=1" manage_proj_cat_add_token -b "$jar" -c "$jar")"
curl -s -o /dev/null --max-time 60 -b "$jar" -c "$jar" --data-urlencode "manage_proj_cat_add_token=$ctok" \
    --data "project_id=1&name=General" "$BASE/manage_proj_cat_add.php"
cat_id="$(curl -s -b "$jar" -c "$jar" "$BASE/bug_report_page.php" | sed -nE 's/.*option value="([0-9]+)" selected.*/\1/p' | sed -n 1p)"
tok="$(form_value "$BASE/bug_report_page.php" bug_report_token -b "$jar" -c "$jar")"
[ -n "$tok" ] || { echo "!!! no bug_report_token" >&2; exit 1; }
curl -s -o /dev/null --max-time 60 -b "$jar" -c "$jar" \
    --data-urlencode "bug_report_token=$tok" --data "project_id=1&category_id=${cat_id}&summary=Hello+from+ePHPm&description=Created+by+the+recipe+smoke+test" \
    "$BASE/bug_report.php"
expect_body "$BASE/view_all_bug_page.php" "Hello from ePHPm" -b "$jar" -c "$jar"

out="$(run_in ephpm php -r 'echo PHP_VERSION;')"
echo "==> embedded php: $out"
