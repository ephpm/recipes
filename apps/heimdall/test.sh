#!/usr/bin/env bash
# Smoke test: the dashboard renders after the start-up migration, an
# application tile is added through the "Add application" form (CSRF token
# + session) and shows on the dashboard, and the item list and artisan work.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28407
recipe_init heimdall
export APP_URL="$BASE"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 180

    # 1. add an application tile through the web form
    local jar tok loc
    jar="$(cookie_jar)"
    tok="$(form_value "$BASE/items/create" "_token" -c "$jar" -b "$jar")"
    [ -n "$tok" ] || { echo "!!! no CSRF token on /items/create" >&2; return 1; }
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' -c "$jar" -b "$jar" \
        --data-urlencode "_token=$tok" --data-urlencode "title=ePHPm Recipe Tile" \
        --data-urlencode "url=https://ephpm.dev/" --data-urlencode "colour=#161b1f" \
        --data-urlencode "pinned=1" --data-urlencode "appid=null" --data-urlencode "tags[]=0" "$BASE/items")"
    case "$loc" in
        "$BASE"/|"$BASE"/dash*|"$BASE") echo "==> item created, redirected to $loc" ;;
        *) echo "!!! item creation redirected to '$loc'" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac

    # 2. read it back: the dashboard and the item list
    expect_body "$BASE/" 'ePHPm Recipe Tile' -c "$jar" -b "$jar"
    expect_body "$BASE/items" 'ePHPm Recipe Tile' -c "$jar" -b "$jar"

    # 3. artisan on the embedded PHP sees the same database
    local out
    out="$(run_in ephpm ephpm php artisan migrate:status --no-ansi)"
    case "$out" in
        *Ran*) echo "==> artisan migrate:status reports migrations as run" ;;
        *) echo "!!! unexpected migrate:status output:" >&2; echo "$out" >&2; return 1 ;;
    esac

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
