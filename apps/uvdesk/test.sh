#!/usr/bin/env bash
# Smoke test: the entrypoint creates the schema, loads UVdesk's default data
# and the super admin (what the web setup wizard does); the helpdesk front
# page answers, the admin logs in through the member login form, creates a
# ticket through the "Create ticket" form and reads it back (ticket list
# XHR and ticket page). Runs against the MariaDB compose file.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28507
recipe_init uvdesk
export UVDESK_SITE_URL="$BASE"
export UVDESK_ADMIN_EMAIL="admin@example.com"
export UVDESK_ADMIN_PASSWORD="Recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/en/" 200 600
    for _ in $(seq 1 60); do
        compose logs ephpm 2>/dev/null | grep "UVdesk is ready" >/dev/null && break
        sleep 2
    done

    # 1. real workflow: log in through the member login form
    local jar loc; jar="$(cookie_jar)"
    curl -s -b "$jar" -c "$jar" -o /dev/null "$BASE/en/member/login"
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 60 -b "$jar" -c "$jar" \
        --data-urlencode "_username=$UVDESK_ADMIN_EMAIL" --data-urlencode "_password=$UVDESK_ADMIN_PASSWORD" \
        "$BASE/en/member/login")"
    case "$loc" in
        */member/dashboard*) echo "==> logged in -> $loc" ;;
        *) echo "!!! login redirected to '$loc'" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac
    expect_status "$BASE/en/member/dashboard" 200 -b "$jar" -c "$jar"

    # 2. create a ticket through the agent's "Create ticket" form, read it back
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 60 -b "$jar" -c "$jar" \
        --data-urlencode "name=Ada Customer" --data-urlencode "from=ada@example.com" --data "type=1" \
        --data-urlencode "subject=Recipe smoke-test ticket" \
        --data-urlencode "reply=Created by the ePHPm recipe test" \
        "$BASE/en/member/ticket/save")"
    case "$loc" in
        */member/ticket/view/*) echo "==> ticket created -> $loc" ;;
        *) echo "!!! ticket form redirected to '$loc'" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac
    expect_body "$BASE/en/member/tickets/xhr" "Recipe smoke-test ticket" -b "$jar" -c "$jar" \
        -H "X-Requested-With: XMLHttpRequest"
    expect_body "$loc" "Recipe smoke-test ticket" -b "$jar" -c "$jar"

    # 3. the console runs on the embedded PHP
    run_in ephpm uvdesk about 2>/dev/null | grep -i "symfony" >/dev/null \
        || { echo "!!! uvdesk console not working" >&2; return 1; }
    echo "==> uvdesk console works"

    compose down -v --remove-orphans
}

run_variant compose.yml
