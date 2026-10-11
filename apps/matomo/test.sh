#!/usr/bin/env bash
# Smoke test: drive Matomo's web installer end to end (system check, database
# — prefilled from MATOMO_DATABASE_* —, tables, superuser, first website,
# finish), log in, read the site back through the reporting API with an app
# token, record a tracking hit, and run the console on the embedded PHP.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28310
recipe_init matomo

ADMIN_PASS="recipe-pass-123"

compose_up
wait_http "$BASE/" 200 180
expect_body "$BASE/" 'Installation'

jar="$(cookie_jar)"
step() { echo "==> installer: $1"; }

# 1. the installer, step by step (MATOMO_DATABASE_* prefill the DB form)
step systemCheck;      expect_body "$BASE/index.php?action=systemCheck" 'Next' -c "$jar" -b "$jar"
step databaseSetup;    expect_status "$BASE/index.php?action=databaseSetup" 302 -c "$jar" -b "$jar" \
    --data "host=db&username=matomo&password=matomo&dbname=matomo&tables_prefix=matomo_&adapter=PDO%5CMYSQL&schema=Mysql&submit=Next"
step tablesCreation;   expect_body "$BASE/index.php?action=tablesCreation" 'Tables created with success|Next' -c "$jar" -b "$jar"
step setupSuperUser;   expect_status "$BASE/index.php?action=setupSuperUser" 302 -c "$jar" -b "$jar" \
    --data "login=admin&password=$ADMIN_PASS&password_bis=$ADMIN_PASS&email=admin%40example.com&submit=Next"
step firstWebsiteSetup; expect_status "$BASE/index.php?action=firstWebsiteSetup" 302 -c "$jar" -b "$jar" \
    --data-urlencode "siteName=ePHPm Recipe" --data "url=https%3A%2F%2Fephpm.dev&timezone=UTC&ecommerce=0&submit=Next"
step trackingCode;     expect_body "$BASE/index.php?action=trackingCode" 'Matomo [0-9.]+ &rsaquo; Installation' -c "$jar" -b "$jar"   # (the snippet itself is rendered client-side)
step finished;         expect_status "$BASE/index.php?action=finished" 302 -c "$jar" -b "$jar" \
    --data "do_not_track=1&anonymise_ip=1&submit=Continue"
run_in ephpm test -f config/config.ini.php || { echo "!!! config/config.ini.php not written" >&2; exit 1; }
expect_body "$BASE/" 'form_login'                       # installed: the login form

# 2. real workflow: log in through the web form, then use the reporting API
nonce="$(form_value "$BASE/index.php?module=Login" form_nonce -c "$jar" -b "$jar")"
[ -n "$nonce" ] || { echo "!!! no form_nonce on the login form" >&2; exit 1; }
expect_status "$BASE/index.php?module=Login&action=" 302 -c "$jar" -b "$jar" \
    --data-urlencode "form_nonce=$nonce" --data "form_login=admin&form_password=$ADMIN_PASS&form_redirect=/"
expect_body "$BASE/index.php?module=CoreHome&action=index&idSite=1&period=day&date=today" 'ePHPm Recipe' -b "$jar"
# an app-specific token, then the site list through the API
token="$(curl -s "$BASE/index.php" --data "module=API&method=UsersManager.createAppSpecificTokenAuth&userLogin=admin&passwordConfirmation=$ADMIN_PASS&description=recipe-smoke-test&format=json" \
    | sed -n 's/.*"value":"\([0-9a-f]*\)".*/\1/p')"
[ -n "$token" ] || { echo "!!! no token_auth from the API" >&2; exit 1; }
expect_body "$BASE/index.php" '"name":"ePHPm Recipe"' --data "module=API&method=SitesManager.getAllSites&format=json&token_auth=$token"

# 3. a tracking request is accepted (what matomo.js sends)
expect_status "$BASE/matomo.php?idsite=1&rec=1&url=https%3A%2F%2Fephpm.dev%2F&action_name=smoke&apiv=1" 200
expect_body "$BASE/index.php" '"visits":[1-9]' --data "module=API&method=Live.getCounters&idSite=1&lastMinutes=30&format=json&token_auth=$token"

# 4. the console runs on the embedded PHP (archiving is what MATOMO_ARCHIVE_INTERVAL schedules)
run_in ephpm ./console core:version | grep -E '^[0-9]+\.[0-9]+' >/dev/null || { echo "!!! ./console core:version failed" >&2; exit 1; }
run_in ephpm ./console core:archive --url="http://127.0.0.1:8080/" >/dev/null || { echo "!!! ./console core:archive failed" >&2; exit 1; }
echo "==> ./console core:version and core:archive ran on the embedded PHP"

# 5. the config and code-only paths are not served
expect_status "$BASE/config/config.ini.php" 403
expect_status "$BASE/core/Version.php" 403
expect_status "$BASE/plugins/Login/Controller.php" 403
rm -f "$jar"
