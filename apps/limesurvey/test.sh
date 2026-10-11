#!/usr/bin/env bash
# Smoke test: the container installs LimeSurvey with console.php on first
# start; then log in to the admin through its form (path-format URLs,
# /index.php/admin/... — no PATH_INFO needed), create a survey (LimeSurvey 7
# creates it and opens the new editor), read it back in the survey list and
# through the REST API (/rest/v1/..., bearer token), and check private paths.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28610
recipe_init limesurvey
export ADMIN_PASSWORD="Recipe-Pass-6610"

compose_up
wait_http "$BASE/" 200 300                                  # after console.php install

# 1. real workflow: log in to the administration
jar="$(cookie_jar)"
login="$BASE/index.php/admin/authentication/sa/login"
page="$(curl -s -c "$jar" -b "$jar" "$login")"
csrf="$(printf '%s' "$page" | grep -oE 'value="[^"]*" name="YII_CSRF_TOKEN"' | sed -n '1s/value="\([^"]*\)".*/\1/p')"
[ -n "$csrf" ] || { echo "!!! no YII_CSRF_TOKEN on the login form" >&2; exit 1; }
loc="$(curl -s -o /dev/null -w '%{redirect_url}' -c "$jar" -b "$jar" "$login" --data-urlencode "YII_CSRF_TOKEN=$csrf" \
    --data "authMethod=Authdb&user=admin&loginlang=default&action=login&width=1200&login_submit=login" \
    --data-urlencode "password=$ADMIN_PASSWORD")"
case "$loc" in
    *"/admin/index"*) echo "==> logged in -> $loc" ;;
    *) echo "!!! login redirected to '$loc'" >&2; compose logs --tail=40 ephpm >&2; exit 1 ;;
esac
expect_body "$BASE/index.php/admin/index" '<title>LimeSurvey' -L -c "$jar" -b "$jar"

# 2. create a record: a new survey (LimeSurvey 7 creates it, then opens the editor)
loc="$(curl -s -o /dev/null -L -w '%{url_effective}' -c "$jar" -b "$jar" "$BASE/index.php/surveyAdministration/newSurvey")"
sid="$(printf '%s' "$loc" | sed -n 's|.*/survey/\([0-9]*\).*|\1|p')"
[ -n "$sid" ] || { echo "!!! newSurvey did not open the editor on a survey: '$loc'" >&2; exit 1; }
echo "==> survey $sid created, editor at $loc"
expect_body "$BASE/editor/" 'Limesurvey Editor'                # the editor's static app
expect_body "$BASE/index.php/surveyAdministration/listsurveys" "$sid" -c "$jar" -b "$jar"
#    … and read it back through the REST API the editor uses
token="$(curl -s "$BASE/rest/v1/auth" -H 'Content-Type: application/json' \
    --data "{\"username\":\"admin\",\"password\":\"$ADMIN_PASSWORD\"}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
[ -n "$token" ] || { echo "!!! no token from /rest/v1/auth" >&2; exit 1; }
expect_body "$BASE/rest/v1/survey" "\"sid\":$sid" -H "Authorization: Bearer $token"
expect_body "$BASE/rest/v1/survey-detail/$sid" "\"sid\":$sid" -H "Authorization: Bearer $token"

# 3. what LimeSurvey's .htaccess files deny
expect_status "$BASE/application/config/config.php" 403
expect_status "$BASE/vendor/autoload.php" 403
expect_status "$BASE/tmp/runtime/" 403
# not served as a file; the router answers — with ePHPm's bare 500 instead of
# LimeSurvey's 404 page, see issues/limesurvey.md
[ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/info.php")" != 200 ] || { echo "!!! /info.php is served" >&2; exit 1; }

# 4. the console on the embedded PHP
run_in ephpm php application/commands/console.php updatedb >/dev/null \
    || { echo "!!! console.php updatedb failed" >&2; exit 1; }
echo "==> application/commands/console.php ran on the embedded PHP"
rm -f "$jar"
