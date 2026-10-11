#!/usr/bin/env bash
# Smoke test: run LinkAce's web setup wizard (requirements, database +
# migrations, admin account), log in through the login form, add a bookmark
# through the web form and read it back, and run the scheduler once inside
# the scheduler service. Runs against the MariaDB compose file (the only
# variant: see issues/linkace.md for why the embedded database cannot load
# LinkAce's schema dump).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28101
recipe_init linkace
# LinkAce's TrustHosts middleware answers 400 to any Host other than APP_URL's.
export APP_URL="$BASE"

# csrf URL — GET the page (with the cookie jar) and print its CSRF token
# (no `head`/`grep -q` after a pipe: under pipefail an early exit kills the
# writer with SIGPIPE and fails the pipeline)
csrf() {
    curl -s --max-time 30 -b "$jar" -c "$jar" "$1" \
        | sed -nE 's/.*name="_token" value="([^"]+)".*/\1/p' | sed -n 1p
}

# expect_redirect URL location-substring [curl args...] — POST and check where it redirects
expect_redirect() {
    local url="$1" want="$2"; shift 2
    local loc
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 180 "$@" "$url" || true)"
    case "$loc" in
        *"$want"*) echo "==> $url -> $loc" ;;
        *) echo "!!! $url redirected to '$loc' (wanted *$want*)" >&2
           compose logs --tail=80 >&2 || true
           return 1 ;;
    esac
}

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    local db_host="$2" db_user="$3" db_pass="$4"
    echo "=== variant: $1 ==="
    compose_up
    # / redirects to the setup wizard until the setup is completed
    wait_http "$BASE/setup/start" 200 180
    expect_body "$BASE/_health" "^Ok"

    jar="$(cookie_jar)"
    local tok

    # 1. requirements: the Continue button is only enabled when every check passed
    expect_body "$BASE/setup/requirements" 'btn btn-primary' -b "$jar" -c "$jar"

    # 2. database step — runs migrate:fresh inside the request
    tok="$(csrf "$BASE/setup/database")"
    expect_redirect "$BASE/setup/database" "/setup/account" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data "connection=mysql&db_host=$db_host&db_port=3306&db_name=linkace&db_user=$db_user" \
        --data-urlencode "db_password=$db_pass"

    # 3. admin account (logs the new user in)
    tok="$(csrf "$BASE/setup/account")"
    expect_redirect "$BASE/setup/account" "/setup/complete" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data "name=admin&email=admin%40example.com&password=recipe-pass-123&password_confirmation=recipe-pass-123"
    expect_body "$BASE/setup/complete" "Setup completed" -b "$jar" -c "$jar"

    # 4. real workflow: log in through the login form with a fresh session
    jar="$(cookie_jar)"
    tok="$(csrf "$BASE/login")"
    expect_redirect "$BASE/login" "/dashboard" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data "email=admin%40example.com&password=recipe-pass-123"
    expect_body "$BASE/dashboard" "Dashboard" -b "$jar" -c "$jar"

    # 5. add a bookmark through the web form and read it back on the links page
    #    (LinkAce fetches the URL's HTML meta, so point it at ePHPm itself)
    tok="$(csrf "$BASE/links/create")"
    expect_redirect "$BASE/links" "/links/" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data-urlencode "url=http://127.0.0.1:8080/_health" \
        --data-urlencode "title=Hello from ePHPm"
    expect_body "$BASE/links" "Hello from ePHPm" -b "$jar" -c "$jar"

    # 6. the scheduler service can run the schedule against the same database
    local out
    out="$(run_in scheduler ephpm php artisan schedule:run)"
    echo "$out"
    case "$out" in
        *"No scheduled commands"*|*Running*) echo "==> scheduler ran artisan schedule:run" ;;
        *) echo "!!! artisan schedule:run failed in the scheduler service" >&2; return 1 ;;
    esac

    compose down -v --remove-orphans
}

run_variant compose.yml db linkace linkace
