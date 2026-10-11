#!/usr/bin/env bash
# Smoke test: wait for the first-start install, log in as the admin through
# the forum's own /login endpoint (session cookie + CSRF token, as the
# browser does), start a discussion through the JSON:API and read it back
# from the API and the server-rendered discussion page, and run the console.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28404
recipe_init flarum
# Links, redirects and the session cookie are built from FORUM_URL.
export FORUM_URL="$BASE"
export FLARUM_ADMIN_PASS="Recipe-Flarum-9731"

# csrf — GET the forum with the cookie jar and print the session's CSRF token
csrf() {
    curl -s --max-time 60 -b "$jar" -c "$jar" "$BASE/" | sed -nE 's/.*"csrfToken":"([^"]+)".*/\1/p' | head -1
}

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 300
    expect_body "$BASE/" "Flarum on ePHPm"

    # 1. real workflow: log in (the forum's login modal posts JSON to /login)
    jar="$(cookie_jar)"
    local tok resp
    tok="$(csrf)"
    [ -n "$tok" ] || { echo "!!! no csrfToken in the forum payload" >&2; return 1; }
    resp="$(curl -s --max-time 60 -b "$jar" -c "$jar" -H "X-CSRF-Token: $tok" -H 'Content-Type: application/json' \
        --data "{\"identification\":\"admin\",\"password\":\"$FLARUM_ADMIN_PASS\",\"remember\":false}" "$BASE/login")"
    case "$resp" in
        *'"userId":1'*) echo "==> logged in as admin" ;;
        *) echo "!!! login failed: $(printf '%s' "$resp" | head -c 600)" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac

    # 2. start a discussion (tag 1 is the installer's "General" tag) …
    tok="$(csrf)"
    resp="$(curl -s --max-time 60 -b "$jar" -c "$jar" -H "X-CSRF-Token: $tok" -H 'Content-Type: application/vnd.api+json' \
        --data '{"data":{"type":"discussions","attributes":{"title":"Hello from ePHPm","content":"Posted by the recipe smoke test."},"relationships":{"tags":{"data":[{"type":"tags","id":"1"}]}}}}' \
        "$BASE/api/discussions")"
    local id
    id="$(printf '%s' "$resp" | sed -nE 's/^\{"data":\{"type":"discussions","id":"([0-9]+)".*/\1/p')"
    [ -n "$id" ] || { echo "!!! creating a discussion failed: $(printf '%s' "$resp" | head -c 800)" >&2; compose logs --tail=60 ephpm >&2; return 1; }
    echo "==> discussion $id created"
    # … and read it back: the API list (anonymous) and the server-rendered page
    expect_body "$BASE/api/discussions" 'Hello from ePHPm'
    expect_body "$BASE/d/$id" 'Posted by the recipe smoke test'

    # 3. the console on the embedded PHP
    local out
    out="$(run_in ephpm ephpm php flarum info)"
    case "$out" in
        *"Flarum core"*) echo "==> flarum info: $(printf '%s' "$out" | grep -m1 'Flarum core')" ;;
        *) echo "!!! flarum info failed:" >&2; echo "$out" >&2; return 1 ;;
    esac

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.sqlite.yml
