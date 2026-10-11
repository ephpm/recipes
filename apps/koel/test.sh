#!/usr/bin/env bash
# Smoke test: wait for koel:init to finish and the app to serve, log in as
# the default admin through the JSON API, create a playlist and read it
# back, and run a library scan on the embedded PHP.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28104
recipe_init koel
export APP_URL="$BASE"

json() { curl -s --max-time 60 -H 'Accept: application/json' -H 'Content-Type: application/json' "$@"; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # the SPA shell answers 200 once koel:init has migrated and ePHPm is up
    wait_http "$BASE/" 200 300
    expect_body "$BASE/" "<title>Koel</title>"

    # 1. real workflow: log in as the default admin (JSON API) and get a token
    local login token
    login="$(json -X POST --data '{"email":"admin@koel.dev","password":"KoelIsCool"}' "$BASE/api/me")"
    token="$(printf '%s' "$login" | sed -nE 's/.*"token":"([^"]+)".*/\1/p')"
    [ -n "$token" ] || { echo "!!! login did not return a token: $login" >&2; compose logs --tail=80 ephpm >&2; return 1; }
    echo "==> logged in as admin@koel.dev"

    # 2. create a playlist and read it back
    local created
    created="$(json -X POST -H "Authorization: Bearer $token" --data '{"name":"Hello from ePHPm"}' "$BASE/api/playlists")"
    case "$created" in
        *'"name":"Hello from ePHPm"'*) echo "==> playlist created" ;;
        *) echo "!!! playlist creation failed: $created" >&2; compose logs --tail=80 ephpm >&2; return 1 ;;
    esac
    local list
    list="$(json -H "Authorization: Bearer $token" "$BASE/api/playlists")"
    case "$list" in
        *'"name":"Hello from ePHPm"'*) echo "==> playlist listed" ;;
        *) echo "!!! playlist missing from the list: $list" >&2; return 1 ;;
    esac

    # 3. artisan runs on the embedded PHP against the same database and media volume
    local out
    out="$(run_in ephpm ephpm php artisan koel:scan --no-ansi 2>&1)"
    echo "$out" | tail -3
    case "$out" in
        *"Exception"*|*"Error"*) echo "!!! artisan koel:scan failed" >&2; return 1 ;;
        *) echo "==> artisan koel:scan ran" ;;
    esac

    compose down -v --remove-orphans
}

run_variant compose.yml
