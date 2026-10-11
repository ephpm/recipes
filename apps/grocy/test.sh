#!/usr/bin/env bash
# Smoke test: the first request creates and migrates the SQLite database,
# log in as admin through the login form, create a location through the
# REST API (with the session, as the web UI does) and read it back from the
# API and the Locations page.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28406
recipe_init grocy

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # GET / runs the schema migrations (Grocy does this on its root route)
    wait_http "$BASE/" 302 180
    curl -s -L -o /dev/null --max-time 120 "$BASE/"    # (the first answer redirects to / again, as a browser would follow)
    wait_http "$BASE/login" 200 60

    # 1. log in through the form (default account admin / admin)
    local jar loc
    jar="$(cookie_jar)"
    curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/login"
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' -c "$jar" -b "$jar" \
        --data "username=admin&password=admin" "$BASE/login")"
    case "$loc" in
        *invalid*|"") echo "!!! login failed (redirect '$loc')" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
        *) echo "==> logged in, redirected to $loc" ;;
    esac
    expect_body "$BASE/stockoverview" 'Stock overview' -c "$jar" -b "$jar"

    # 2. create a location through the API and read it back
    local resp
    resp="$(curl -s --max-time 60 -c "$jar" -b "$jar" -H 'Content-Type: application/json' \
        --data '{"name":"Pantry from ePHPm","description":"created by the recipe smoke test"}' \
        "$BASE/api/objects/locations")"
    case "$resp" in
        *created_object_id*) echo "==> location created: $resp" ;;
        *) echo "!!! creating a location failed: $(printf '%s' "$resp" | head -c 600)" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac
    expect_body "$BASE/api/objects/locations" 'Pantry from ePHPm' -c "$jar" -b "$jar"
    expect_body "$BASE/locations" 'Pantry from ePHPm' -c "$jar" -b "$jar"

    # 3. not logged in: the API refuses, the UI redirects to the login form
    expect_status "$BASE/api/objects/locations" 401
    expect_status "$BASE/stockoverview" 302

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
