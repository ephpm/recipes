#!/usr/bin/env bash
# Smoke test: SuiteCRM installs silently on the first start, the login page
# answers, the admin logs in through the login form, an Account is created
# and read back through the v4_1 REST API and shown in the web UI, the cron
# service runs cron.php, and the .htaccess-equivalent blocks hold.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28412
recipe_init suitecrm
export SUITECRM_SITE_URL="$BASE"
export SUITECRM_ADMIN_PASSWORD="recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/index.php?action=Login&module=Users" 200 400
    expect_body "$BASE/index.php?action=Login&module=Users" 'name="user_name"'

    # 1. log in through the login form
    local jar
    jar="$(cookie_jar)"
    curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/index.php?action=Login&module=Users"
    curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/index.php" \
        --data "module=Users&action=Authenticate&return_module=Users&return_action=Login&user_name=admin" \
        --data-urlencode "username_password=$SUITECRM_ADMIN_PASSWORD"
    expect_body "$BASE/index.php?module=Home&action=index" 'action=Logout' -b "$jar"

    # 2. REST API (v4_1): log in, create an Account, read it back
    local rest="$BASE/service/v4_1/rest.php" pw sid out id
    pw="$(printf '%s' "$SUITECRM_ADMIN_PASSWORD" | md5sum | cut -d' ' -f1)"
    out="$(curl -s "$rest" --data-urlencode method=login --data-urlencode input_type=JSON --data-urlencode response_type=JSON \
        --data-urlencode "rest_data={\"user_auth\":{\"user_name\":\"admin\",\"password\":\"$pw\"},\"application_name\":\"recipes\"}")"
    sid="$(printf '%s' "$out" | sed -nE 's/^\{"id":"([^"]+)".*/\1/p')"
    [ -n "$sid" ] || { echo "!!! REST login: $out" >&2; compose logs --tail=60 ephpm >&2; return 1; }
    echo "==> REST login ok"
    out="$(curl -s "$rest" --data-urlencode method=set_entry --data-urlencode input_type=JSON --data-urlencode response_type=JSON \
        --data-urlencode "rest_data={\"session\":\"$sid\",\"module_name\":\"Accounts\",\"name_value_list\":[{\"name\":\"name\",\"value\":\"Hello from ePHPm\"},{\"name\":\"industry\",\"value\":\"Technology\"}]}")"
    id="$(printf '%s' "$out" | sed -nE 's/^\{"id":"([^"]+)".*/\1/p')"
    [ -n "$id" ] || { echo "!!! set_entry: $out" >&2; return 1; }
    echo "==> Account $id created"
    expect_body "$rest" '"value":"Hello from ePHPm"' --data-urlencode method=get_entry --data-urlencode input_type=JSON --data-urlencode response_type=JSON \
        --data-urlencode "rest_data={\"session\":\"$sid\",\"module_name\":\"Accounts\",\"id\":\"$id\",\"select_fields\":[\"name\",\"industry\"],\"link_name_to_fields_array\":[]}"
    expect_body "$BASE/index.php?module=Accounts&action=DetailView&record=$id" 'Hello from ePHPm' -b "$jar"

    # 3. the scheduler container runs cron.php (it stamps last_run on the jobs)
    local i=0
    until run_in db mariadb -usuitecrm -psuitecrm suitecrm -N -e "SELECT COUNT(*) FROM schedulers WHERE last_run IS NOT NULL" 2>/dev/null | grep -qv '^0$'; do
        i=$((i + 1)); [ "$i" -ge 30 ] && { echo "!!! cron.php has not run any scheduler" >&2; compose logs --tail=40 cron >&2; return 1; }
        sleep 5
    done
    echo "==> cron.php ran the schedulers"

    # 4. what .htaccess denies is denied
    expect_status "$BASE/config.php" 403
    expect_status "$BASE/suitecrm.log" 403
    expect_status "$BASE/modules/Accounts/Account.php" 403
    expect_status "$BASE/info.php" 404

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
