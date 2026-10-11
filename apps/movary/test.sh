#!/usr/bin/env bash
# Smoke test: the entrypoint migrates and creates the admin; we log in the
# way the login page's JavaScript does (POST /api/authentication/token with
# the page's CSRF token), open the dashboard, and read the account through
# the web app. Runs against the MariaDB compose file and Movary's native-SQLite
# stack (the ePHPm embedded-database variant is not shipped: Movary's
# migrations use ALTER TABLE … ADD CONSTRAINT, see issues/easyappointments.md).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28208
recipe_init movary

export APPLICATION_URL="$BASE"
export ADMIN_EMAIL="admin@example.com"
export ADMIN_PASSWORD="recipe-pass-123"
export ADMIN_NAME="recipeadmin"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/login" 200 300
    for _ in $(seq 1 90); do
        compose logs ephpm 2>/dev/null | grep "Movary is ready" >/dev/null && break
        sleep 2
    done
    compose logs ephpm 2>/dev/null | grep "Movary is ready" >/dev/null \
        || { echo "!!! setup did not finish"; compose logs --tail=80 >&2; return 1; }

    # 1. real workflow: log in as the login page's JS does
    local jar page csrf; jar="$(cookie_jar)"; page="$(native_path "$(mktemp)")"
    curl -s -c "$jar" -o "$page" "$BASE/login"
    csrf="$(grep -o 'name="csrf-token" content="[^"]*"' "$page" | head -n1 | sed 's/.*content="//; s/"$//')"
    [ -n "$csrf" ] || { echo "!!! no CSRF token on the login page" >&2; return 1; }
    expect_body "$BASE/api/authentication/token" '"authToken"' -b "$jar" -c "$jar" \
        -H 'Content-Type: application/json' -H "X-CSRF-Token: $csrf" -H 'X-Movary-Client: Movary Web' -H "Origin: $BASE" \
        --data "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\",\"rememberMe\":false,\"totpCode\":\"\"}"

    # 2. the dashboard and the account page are served to the logged-in user
    expect_body "$BASE/" "recipeadmin" -L -b "$jar" -c "$jar"   # / redirects to the user's dashboard
    expect_status "$BASE/settings/account/general" 200 -b "$jar" -c "$jar"

    # 3. the console runs on the embedded PHP
    local users; users="$(run_in ephpm movary user:list 2>&1 || true)"
    printf '%s\n' "$users" | grep -E "recipeadmin|admin@example" >/dev/null \
        || { echo "!!! movary console cannot list users: $users" >&2; return 1; }
    echo "==> movary console lists the admin"

    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.sqlite.yml
