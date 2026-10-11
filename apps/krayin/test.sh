#!/usr/bin/env bash
# Smoke test: the entrypoint runs `krayin-crm:install` unattended (schema,
# seed data, admin); the admin logs in through the login form, creates a
# person (contact) through the "Create person" form and reads it back on its
# page. Runs against the MariaDB compose file.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28505
recipe_init krayin
export APP_URL="$BASE"
export KRAYIN_ADMIN_EMAIL="admin@example.com"
export KRAYIN_ADMIN_PASSWORD="Recipe-pass-123"

# csrf URL — GET the page (with the cookie jar) and print its CSRF token
csrf() {
    curl -s --max-time 30 -b "$jar" -c "$jar" "$1" \
        | grep -oE '<input[^>]*name="_token"[^>]*>' | sed -nE 's/.*value="([^"]+)".*/\1/p' | sed -n 1p
}

# post_redirect URL location-substring [curl args...] — POST and check where it redirects
post_redirect() {
    local url="$1" want="$2"; shift 2
    local loc
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 120 "$@" "$url" || true)"
    case "$loc" in
        *"$want"*) echo "==> $url -> $loc" ;;
        *) echo "!!! $url redirected to '$loc' (wanted *$want*)" >&2
           compose logs --tail=80 ephpm >&2 || true
           return 1 ;;
    esac
}

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # the installer runs before ePHPm starts listening
    wait_http "$BASE/admin/login" 200 900

    # 1. real workflow: log in through the login form
    jar="$(cookie_jar)"
    local tok
    tok="$(csrf "$BASE/admin/login")"
    post_redirect "$BASE/admin/login" "/admin/dashboard" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data-urlencode "email=$KRAYIN_ADMIN_EMAIL" --data-urlencode "password=$KRAYIN_ADMIN_PASSWORD"
    expect_status "$BASE/admin/dashboard" 200 -b "$jar" -c "$jar"

    # 2. create a person through the form and read it back
    tok="$(csrf "$BASE/admin/contacts/persons/create")"
    post_redirect "$BASE/admin/contacts/persons/create" "/admin/contacts/persons" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" --data "entity_type=persons" \
        --data-urlencode "name=Ada Ephpmrecipe" \
        --data-urlencode "emails[0][value]=ada@example.com" --data-urlencode "emails[0][label]=work" \
        --data-urlencode "contact_numbers[0][value]=5550100" --data-urlencode "contact_numbers[0][label]=work"
    expect_body "$BASE/admin/contacts/persons/view/1" "Ada Ephpmrecipe" -b "$jar" -c "$jar"

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
