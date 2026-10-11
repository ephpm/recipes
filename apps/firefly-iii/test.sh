#!/usr/bin/env bash
# Smoke test: wait for Firefly III to upgrade its database and serve,
# register the first user through the registration form, complete the
# new-user wizard (creates the first asset account), read the account back,
# and hit the cron endpoint the cron sidecar calls.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28103
recipe_init firefly-iii
# Firefly III builds redirects and links from APP_URL.
export APP_URL="$BASE"
CRON_TOKEN="ephpmrecipechangeme0123456789abc"
export STATIC_CRON_TOKEN="$CRON_TOKEN"

# csrf URL — GET the page (with the cookie jar) and print its CSRF token
csrf() {
    curl -s --max-time 30 -b "$jar" -c "$jar" "$1" \
        | sed -nE 's/.*name="_token" value="([^"]+)".*/\1/p' | sed -n 1p
}

# expect_redirect URL location-substring [curl args...] — request and check where it redirects
expect_redirect() {
    local url="$1" want="$2"; shift 2
    local loc
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 120 "$@" "$url" || true)"
    case "$loc" in
        *"$want"*) echo "==> $url -> $loc" ;;
        *) echo "!!! $url redirected to '$loc' (wanted *$want*)" >&2
           compose logs --tail=80 >&2 || true
           return 1 ;;
    esac
}

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # The registration page answers 200 once the database upgrade is done
    # and no user exists yet.
    wait_http "$BASE/register" 200 300
    expect_status "$BASE/" 302

    # 1. register the first user (becomes the owner)
    jar="$(cookie_jar)"
    local tok
    tok="$(csrf "$BASE/register")"
    expect_redirect "$BASE/register" "/home" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data "email=admin%40example.com&password=Ephpm-Recipe-9731&password_confirmation=Ephpm-Recipe-9731&verify_password=0"
    # a user without accounts is sent to the new-user wizard
    expect_redirect "$BASE/home" "/new-user" -b "$jar" -c "$jar"

    # 2. real workflow: the new-user wizard creates the first asset account
    tok="$(csrf "$BASE/new-user")"
    expect_redirect "$BASE/new-user/submit" "$BASE" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data "bank_name=Checking+from+ePHPm&bank_balance=100&amount_currency_id_bank_balance=1&language=en_US"
    # (the account list page is rendered client-side, so read the record from
    # the database and open the account's own page)
    local id
    id="$(run_in db mariadb -N -ufirefly -psecret_firefly_password firefly -e "select id from accounts where name='Checking from ePHPm'" | tr -d '[:space:]')"
    [ -n "$id" ] || { echo "!!! asset account not found in the database" >&2; compose logs --tail=80 ephpm >&2; return 1; }
    echo "==> asset account #$id created through the wizard"
    expect_body "$BASE/accounts/show/$id" "Checking from ePHPm" -b "$jar" -c "$jar"

    # 3. the cron endpoint the cron sidecar calls once a day
    expect_status "$BASE/api/v1/cron/$CRON_TOKEN" 200

    # 4. artisan runs on the embedded PHP against the same database
    local out
    out="$(run_in ephpm ephpm php artisan firefly-iii:report-integrity --no-ansi 2>&1)"
    echo "$out" | tail -3
    case "$out" in
        *"Exception"*|*"Error"*) echo "!!! artisan firefly-iii:report-integrity failed" >&2; return 1 ;;
        *) echo "==> artisan firefly-iii:report-integrity ran" ;;
    esac

    compose down -v --remove-orphans
}

run_variant compose.yml
