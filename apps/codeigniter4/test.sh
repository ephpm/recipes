#!/usr/bin/env bash
# Smoke test: the welcome page renders, the migration ran, and a guestbook
# entry posted over HTTP is read back over HTTP (MariaDB stack, then the
# single-container embedded variant).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28013
recipe_init codeigniter4

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 180
    expect_body "$BASE/" "CodeIgniter"

    # migration present (the embedded variant migrates in the background)
    local i=0
    until curl -s -o /dev/null -w '%{http_code}' "$BASE/guestbook" | grep 200 >/dev/null; do
        i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! guestbook table not ready"; compose logs --tail=60 ephpm; return 1; }
        sleep 2
    done
    expect_status "$BASE/guestbook" 201 --data-urlencode "name=ePHPm" --data-urlencode "message=Hello from the recipe"
    expect_body "$BASE/guestbook" "Hello from the recipe"
    run_in ephpm ephpm php spark migrate:status --no-header | grep "CreateGuestbook" >/dev/null
    echo "==> guestbook round trip through MySQLi OK"

    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.embedded.yml
