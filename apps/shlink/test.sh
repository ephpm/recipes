#!/usr/bin/env bash
# Smoke test: the entrypoint initialises the schema and the initial API key;
# we create a short URL through the REST API, follow it (302 to the long
# URL), and list it back. Runs against the MariaDB compose file and Shlink's
# native-SQLite single container (the ePHPm embedded-database variant is not
# shipped: see issues/shlink.md).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28203
recipe_init shlink

export DEFAULT_DOMAIN="127.0.0.1:$PORT"
export INITIAL_API_KEY="recipe-api-key-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/rest/health" 200 240
    expect_body "$BASE/rest/health" '"status":\s*"pass"'

    # 1. the entrypoint's init (schema + API key) finished: the API answers 200
    for _ in $(seq 1 60); do
        [ "$(curl -s -o /dev/null -w '%{http_code}' -H "X-Api-Key: $INITIAL_API_KEY" "$BASE/rest/v3/short-urls")" = 200 ] && break
        sleep 2
    done
    expect_status "$BASE/rest/v3/short-urls" 200 -H "X-Api-Key: $INITIAL_API_KEY"

    # 2. real workflow: create a short URL, follow it, list it
    local out code
    out="$(curl -s --max-time 30 -H "X-Api-Key: $INITIAL_API_KEY" -H 'Content-Type: application/json' \
        --data '{"longUrl":"https://ephpm.dev/recipe","customSlug":"ephpm"}' "$BASE/rest/v3/short-urls")"
    printf '%s\n' "$out" | grep '"shortCode":"ephpm"' >/dev/null \
        || { echo "!!! short URL not created: $out" >&2; compose logs --tail=80 >&2; return 1; }
    echo "==> short URL created: $(printf '%s' "$out" | grep -o '"shortUrl":"[^"]*"')"
    code="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$BASE/ephpm")"
    [ "$code" = "302 https://ephpm.dev/recipe" ] \
        || { echo "!!! /ephpm -> $code (wanted 302 https://ephpm.dev/recipe)" >&2; compose logs --tail=80 >&2; return 1; }
    echo "==> /ephpm -> $code"
    expect_body "$BASE/rest/v3/short-urls/ephpm/visits" '"totalItems":\s*1' -H "X-Api-Key: $INITIAL_API_KEY"
    expect_body "$BASE/rest/v3/short-urls" '"longUrl":"https://ephpm.dev/recipe"' -H "X-Api-Key: $INITIAL_API_KEY"

    # 3. the CLI runs on the embedded PHP
    run_in ephpm shlink short-url:list | grep 'ephpm.dev/recipe' >/dev/null \
        || { echo "!!! shlink CLI does not list the URL" >&2; return 1; }
    echo "==> shlink CLI lists the URL"

    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.sqlite.yml
