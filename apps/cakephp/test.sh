#!/usr/bin/env bash
# Smoke test: the landing page renders, the migration ran, and a guestbook
# entry is created over HTTP through the skeleton's CSRF middleware and read
# back as JSON (MariaDB stack).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28015
recipe_init cakephp

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # The skeleton's templates/Pages/home.php throws NotFoundException when
    # debug is off (by design: "replace this page"), so the landing page is a
    # 404 in production and the app is probed through the demo route.
    wait_http "$BASE/guestbook" 200 180
    expect_status "$BASE/" 404

    # CSRF: the token comes with the cookie on the first GET; send it back as a header.
    local jar tok; jar="$(cookie_jar)"
    tok="$(curl -s -c "$jar" "$BASE/guestbook" | sed -nE 's/.*"csrfToken":"([^"]+)".*/\1/p' | sed 's#\\/#/#g')"
    [ -n "$tok" ] || { echo "!!! no CSRF token"; return 1; }
    expect_status "$BASE/guestbook/add" 201 -b "$jar" -H "X-CSRF-Token: $tok" \
        --data-urlencode "name=ePHPm" --data-urlencode "message=Hello from the recipe"
    expect_status "$BASE/guestbook/add" 403 --data-urlencode "name=x" --data-urlencode "message=no token"
    expect_body "$BASE/guestbook" "Hello from the recipe"
    rm -f "$jar"
    run_in ephpm ephpm php bin/cake.php migrations status | grep "CreateGuestbook" >/dev/null
    echo "==> guestbook round trip (CSRF + ORM + MySQL driver) OK"

    compose down -v --remove-orphans
}

run_variant compose.yml
