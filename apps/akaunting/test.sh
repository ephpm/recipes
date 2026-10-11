#!/usr/bin/env bash
# Smoke test: wait for `artisan install` to finish and the app to serve,
# log in through the login form, then, through the REST API (HTTP basic
# auth, as Akaunting documents), create a customer and read it back; run
# the scheduler once inside the scheduler service.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28108
recipe_init akaunting
export APP_URL="$BASE"
ADMIN="admin@example.com"
PASS="Recipe-Pass-9731"

# csrf URL — GET the page (with the cookie jar) and print its CSRF token
csrf() {
    curl -s --max-time 60 -b "$jar" -c "$jar" "$1" \
        | sed -nE 's/.*name="_token" value="([^"]+)".*/\1/p' | sed -n 1p
}

api() { curl -s --max-time 60 -u "$ADMIN:$PASS" -H 'Accept: application/json' "$@"; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # the login page answers 200 once the installer has run
    wait_http "$BASE/auth/login" 200 420

    # 1. real workflow: log in through the login form
    local jar tok
    jar="$(cookie_jar)"
    tok="$(csrf "$BASE/auth/login")"
    local login
    login="$(curl -s --max-time 60 -b "$jar" -c "$jar" -H 'Accept: application/json' -H 'X-Requested-With: XMLHttpRequest' \
        --data-urlencode "_token=$tok" --data-urlencode "email=$ADMIN" --data-urlencode "password=$PASS" "$BASE/auth/login")"
    case "$login" in
        *'"success":true'*|*'"redirect"'*) echo "==> logged in through the login form" ;;
        *) echo "!!! login failed: $login" >&2; compose logs --tail=80 ephpm >&2; return 1 ;;
    esac

    # 2. the REST API with basic auth: ping, create a customer, read it back
    expect_body "$BASE/api/ping" '"status":"ok"' -u "$ADMIN:$PASS" -H 'Accept: application/json'
    # (every Akaunting API call carries the company it acts on — company_id=1
    # is the company `artisan install` created — and the contacts endpoint
    # derives its permission from `search=type:customer`. No email: Akaunting
    # validates it with `email:dns`, and checkdnsrr() hangs on v0.11.3 —
    # issues/akaunting.md)
    local created
    created="$(api --data "type=customer&currency_code=USD&enabled=1" --data-urlencode "name=Hello from ePHPm" "$BASE/api/contacts?company_id=1&search=type:customer")"
    case "$created" in
        *'"name":"Hello from ePHPm"'*) echo "==> customer created through the API" ;;
        *) echo "!!! customer creation failed: $created" >&2; compose logs --tail=80 ephpm >&2; return 1 ;;
    esac
    local list
    list="$(api "$BASE/api/contacts?company_id=1&search=type:customer")"
    case "$list" in
        *'"name":"Hello from ePHPm"'*) echo "==> customer listed by the API" ;;
        *) echo "!!! customer missing from the API list: $list" >&2; return 1 ;;
    esac

    # 3. the scheduler service can run the schedule against the same database
    local out
    out="$(run_in scheduler ephpm php artisan schedule:run)"
    echo "$out" | tail -3
    case "$out" in
        *"No scheduled commands"*|*Running*) echo "==> scheduler ran artisan schedule:run" ;;
        *) echo "!!! artisan schedule:run failed in the scheduler service" >&2; return 1 ;;
    esac

    compose down -v --remove-orphans
}

run_variant compose.yml
