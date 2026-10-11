#!/usr/bin/env bash
# Smoke test: the entrypoint migrates and creates the admin; the public
# status page answers, an API token for that admin is issued on the
# embedded PHP, a component and an incident are created through the REST API
# and read back (API and status page). Runs against the MariaDB compose file
# and the native-SQLite single container.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28506
recipe_init cachet
export APP_URL="$BASE"
export CACHET_ADMIN_EMAIL="admin@example.com"
export CACHET_ADMIN_PASSWORD="Recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 600
    for _ in $(seq 1 60); do
        compose logs ephpm 2>/dev/null | grep "Cachet is ready" >/dev/null && break
        sleep 2
    done
    expect_status "$BASE/dashboard/login" 200

    # 1. an API token for the admin, issued on the embedded PHP (Sanctum)
    local token
    token="$(run_in ephpm ephpm php artisan tinker --execute \
        'echo \Cachet\Models\User::where("email", getenv("CACHET_ADMIN_EMAIL"))->firstOrFail()->createToken("recipe-test", ["*"])->plainTextToken;' \
        | tr -d '\r' | tail -n 1)"
    case "$token" in
        *"|"*) echo "==> API token issued" ;;
        *) echo "!!! could not issue an API token: $token" >&2; return 1 ;;
    esac

    # 2. create a component and an incident through the API and read them back
    local auth=(-H "Authorization: Bearer $token" -H "Accept: application/json")
    expect_status "$BASE/api/components" 201 "${auth[@]}" \
        --data-urlencode "name=Recipe API" --data "status=1&enabled=1"
    expect_body "$BASE/api/components" "Recipe API" "${auth[@]}"
    expect_status "$BASE/api/incidents" 201 "${auth[@]}" \
        --data-urlencode "name=Recipe smoke-test incident" \
        --data-urlencode "message=Created by the ePHPm recipe test" --data "status=1&visible=1"
    expect_body "$BASE/api/incidents" "Recipe smoke-test incident" "${auth[@]}"
    expect_body "$BASE/" "Recipe smoke-test incident"

    compose down -v --remove-orphans
}

run_variant compose.yml
NO_BUILD=1 run_variant compose.sqlite.yml
