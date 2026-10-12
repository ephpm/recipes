#!/usr/bin/env bash
# Smoke test: wait for migrations + the backend user, check the API root and
# the backend web app, get a token for the backend user, build an API through
# the backend API (an action + a public operation) and call it, and check
# that the cron sidecar executes a Fusio cronjob.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28522
recipe_init fusio
export FUSIO_URL="$BASE" FUSIO_APPS_URL="$BASE/apps"
export FUSIO_BACKEND_PW="Recipe-Pass-4417"

compose_up
wait_http "$BASE/" 200 300
fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
expect_body "$BASE/" '"title": "Fusio"'
expect_body "$BASE/apps/fusio/" "$BASE"                   # backend app, API URL written by marketplace:env

# 1. a token for the backend user (OAuth2 client_credentials with the user's credentials)
token="$(curl -s -u "admin:$FUSIO_BACKEND_PW" --data 'grant_type=client_credentials' "$BASE/authorization/token" \
    | sed -n 's/.*"access_token": *"\([^"]*\)".*/\1/p')"
[ -n "$token" ] || { echo "!!! no access token for the backend user" >&2; exit 1; }
auth=(-H "Authorization: Bearer $token" -H 'Content-Type: application/json')
expect_body "$BASE/backend/account" '"name": "admin"' "${auth[@]}"

# 2. build an API: an action, a public GET operation that runs it, then call it
expect_body "$BASE/backend/action" '"success": true' "${auth[@]}" \
    --data '{"name":"ephpm-hello","class":"Fusio.Adapter.Util.Action.UtilStaticResponse","config":{"response":"{\"hello\":\"from ePHPm\"}"}}'
expect_body "$BASE/backend/operation" '"success": true' "${auth[@]}" \
    --data '{"name":"ephpm.hello","stability":1,"httpMethod":"GET","httpPath":"/ephpm/hello","httpCode":200,"public":true,"outgoing":"schema://Passthru","action":"action://ephpm-hello"}'
expect_body "$BASE/ephpm/hello" '"hello": "from ePHPm"'
expect_body "$BASE/backend/operation?search=ephpm" '"httpPath": "/ephpm/hello"' "${auth[@]}"

# 3. the cron sidecar runs Fusio's cronjobs (`system:cronjob` every minute)
expect_body "$BASE/backend/cronjob" '"success": true' "${auth[@]}" \
    --data '{"name":"ephpm-tick","cron":"* * * * *","action":"action://ephpm-hello"}'
i=0
until [ "$(run_in db mariadb -N -ufusio -pfusio-db-password fusio -e "SELECT exit_code FROM fusio_cronjob WHERE name='ephpm-tick' AND execute_date IS NOT NULL" 2>/dev/null)" = "0" ]; do
    i=$((i + 1)); [ "$i" -ge 150 ] && { echo "!!! the cronjob was not executed" >&2; compose logs --tail=40 cron >&2; exit 1; }
    sleep 1
done
echo "==> the cron sidecar executed the cronjob"

# 4. the CLI on the embedded PHP
expect_cli="$(run_in ephpm ephpm php bin/fusio system:check user 2>&1 || true)"
echo "==> bin/fusio system:check user: $(printf '%s' "$expect_cli" | grep -v Deprecated | grep . | tail -1)"
