#!/usr/bin/env bash
# Smoke test: wait for BookStack to migrate and serve, log in as the seeded
# admin through the login form, create a book through the web form and read
# it back, and run artisan through the embedded PHP. Runs against the
# MariaDB compose file (the only variant: see issues/bookstack.md for why the
# embedded database cannot run BookStack's migrations).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28102
recipe_init bookstack
# BookStack builds redirects and links from APP_URL.
export APP_URL="$BASE"

# csrf URL — GET the page (with the cookie jar) and print its CSRF token
csrf() {
    curl -s --max-time 30 -b "$jar" -c "$jar" "$1" \
        | sed -nE 's/.*name="_token" value="([^"]+)".*/\1/p' | sed -n 1p
}

# expect_redirect URL location-substring [curl args...] — POST and check where it redirects
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
    # / redirects to /login (302) until logged in; /login itself is 200 once
    # the database is migrated.
    wait_http "$BASE/login" 200 240
    expect_status "$BASE/" 302

    # 1. real workflow: log in as the seeded admin
    jar="$(cookie_jar)"
    local tok
    tok="$(csrf "$BASE/login")"
    expect_redirect "$BASE/login" "$BASE" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data "email=admin%40admin.com&password=password"
    expect_body "$BASE/" "Shelves" -b "$jar" -c "$jar"

    # 2. create a book through the web form and read it back
    tok="$(csrf "$BASE/create-book")"
    expect_redirect "$BASE/books" "/books/hello-from-ephpm" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data-urlencode "name=Hello from ePHPm" \
        --data-urlencode "description_html=<p>Created by the recipe smoke test</p>"
    expect_body "$BASE/books" "Hello from ePHPm" -b "$jar" -c "$jar"
    expect_body "$BASE/books/hello-from-ephpm" "Created by the recipe smoke test" -b "$jar" -c "$jar"

    # 3. artisan runs on the embedded PHP against the same database
    local out
    out="$(run_in ephpm ephpm php artisan migrate:status --no-ansi)"
    case "$out" in
        *Ran*) echo "==> artisan migrate:status reports migrations as run" ;;
        *) echo "!!! unexpected migrate:status output:" >&2; echo "$out" >&2; return 1 ;;
    esac

    compose down -v --remove-orphans
}

run_variant compose.yml
