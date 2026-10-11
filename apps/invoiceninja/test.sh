#!/usr/bin/env bash
# Smoke test: wait for migrations + the first account, log in through the
# JSON API (what the web UI does), create a client with the API token the
# login returns and read it back, and run the scheduler once inside the
# scheduler service.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28109
recipe_init invoiceninja
export APP_URL="$BASE"
ADMIN="admin@example.com"
PASS="Recipe-Pass-9731"

json() { curl -s --max-time 120 -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' "$@"; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # the UI shell answers 200 once the app is up; migrations + the first
    # account take a few minutes on a fresh database
    wait_http "$BASE/" 200 480
    expect_status "$BASE/api/v1/ping" 403     # authenticated endpoint: 403 without a token

    # 1. real workflow: log in through the API (the web app's own login call)
    #    (responses are pretty-printed JSON: flatten the line breaks first)
    local login token
    login="$(json -X POST --data "{\"email\":\"$ADMIN\",\"password\":\"$PASS\"}" "$BASE/api/v1/login" | tr -d '\n\r\t')"
    token="$(printf '%s' "$login" | sed -nE 's/.*"token": ?\{[^}]*"token": ?"([^"]+)".*/\1/p' | sed -n 1p)"
    [ -n "$token" ] || { echo "!!! login did not return an API token: $(printf '%s' "$login" | head -c 600)" >&2; compose logs --tail=80 ephpm >&2; return 1; }
    echo "==> logged in through the API"

    # 2. create a client and read it back
    local created
    created="$(json -X POST -H "X-Api-Token: $token" --data '{"name":"Hello from ePHPm"}' "$BASE/api/v1/clients" | tr -d '\n\r\t' | sed 's/": "/":"/g')"
    case "$created" in
        *'"name":"Hello from ePHPm"'*) echo "==> client created through the API" ;;
        *) echo "!!! client creation failed: $(printf '%s' "$created" | head -c 600)" >&2; compose logs --tail=80 ephpm >&2; return 1 ;;
    esac
    local list
    list="$(json -H "X-Api-Token: $token" "$BASE/api/v1/clients" | tr -d '\n\r\t' | sed 's/": "/":"/g')"
    case "$list" in
        *'"name":"Hello from ePHPm"'*) echo "==> client listed by the API" ;;
        *) echo "!!! client missing from the API list" >&2; return 1 ;;
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
