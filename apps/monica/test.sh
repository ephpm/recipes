#!/usr/bin/env bash
# Smoke test: wait for monica:update and the app to serve, register the
# first account through the registration form, add a contact through the
# web form and read it back, and run the scheduler once inside the
# scheduler service.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28106
recipe_init monica
export APP_URL="$BASE"

# csrf URL — GET the page (with the cookie jar) and print its CSRF token
csrf() {
    curl -s --max-time 60 -b "$jar" -c "$jar" "$1" \
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
    # the registration page answers 200 once monica:update is done
    wait_http "$BASE/register" 200 300
    # with no account yet, the front page sends you to the registration form
    expect_redirect "$BASE/" "/register"

    # 1. real workflow: register the first account (logs in, lands on the dashboard)
    jar="$(cookie_jar)"
    local tok
    tok="$(csrf "$BASE/register")"
    expect_redirect "$BASE/register" "/dashboard" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data "email=admin%40example.com&first_name=Admin&last_name=User&password=Recipe-Pass-9731&password_confirmation=Recipe-Pass-9731&policy=1&lang=en"
    # (the dashboard is a Vue app; the server-rendered shell carries the nav)
    expect_body "$BASE/dashboard" "dashboard" -b "$jar" -c "$jar"
    expect_status "$BASE/login" 302 -b "$jar" -c "$jar"   # already logged in

    # 2. add a contact through the web form and read its own page back
    tok="$(csrf "$BASE/people/add")"
    local loc
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 60 -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" --data "first_name=Hello&last_name=ePHPm&save=true" "$BASE/people")"
    case "$loc" in
        *"/people/"*) echo "==> contact created: $loc" ;;
        *) echo "!!! contact creation redirected to '$loc'" >&2; compose logs --tail=80 ephpm >&2; return 1 ;;
    esac
    expect_body "$loc" "Hello ePHPm" -b "$jar" -c "$jar"

    # 3. the scheduler service can run the schedule against the same database
    local out
    out="$(run_in scheduler ephpm php artisan schedule:run)"
    echo "$out"
    case "$out" in
        *"No scheduled commands"*|*Running*) echo "==> scheduler ran artisan schedule:run" ;;
        *) echo "!!! artisan schedule:run failed in the scheduler service" >&2; return 1 ;;
    esac

    compose down -v --remove-orphans
}

run_variant compose.yml
