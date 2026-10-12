#!/usr/bin/env bash
# Smoke test: the entrypoint installs EspoCRM (schema, admin, config); we
# load the client app, authenticate through the API the way the client
# does, create an Account and read it back, and run the console. Runs
# against the MariaDB compose file (EspoCRM's installer emits MySQL DDL the
# embedded database rejects — no embedded variant).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28211
recipe_init espocrm

export ESPOCRM_SITE_URL="$BASE"
export ESPOCRM_ADMIN_USERNAME="admin"
export ESPOCRM_ADMIN_PASSWORD="recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 420
    # the base image's E2E fixtures (issues/joomla.md) must not be served
    fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
    for _ in $(seq 1 90); do
        compose logs ephpm 2>/dev/null | grep "EspoCRM is ready" >/dev/null && break
        sleep 2
    done
    compose logs ephpm 2>/dev/null | grep "EspoCRM is ready" >/dev/null \
        || { echo "!!! install did not finish"; compose logs --tail=80 >&2; return 1; }

    # 1. the client app and its assets are served (public/ + the client/ symlink)
    expect_body "$BASE/" "<title>EspoCRM</title>|EspoCRM"
    expect_status "$BASE/client/lib/espo.js" 200    # static files from client/, next to public/
    expect_status "$BASE/api/v1/App/user" 401      # the API answers, and asks for credentials

    # 2. real workflow: log in the way the client does, create an Account, read it back
    local auth; auth="$(printf '%s:%s' "$ESPOCRM_ADMIN_USERNAME" "$ESPOCRM_ADMIN_PASSWORD" | base64 | tr -d '\n')"
    expect_body "$BASE/api/v1/App/user" '"userName":"admin"' -H "Espo-Authorization: $auth"
    expect_body "$BASE/api/v1/Account" '"name":"Acme Recipe Ltd"' -H "Espo-Authorization: $auth" \
        -H 'Content-Type: application/json' --data '{"name":"Acme Recipe Ltd","type":"Customer"}'
    expect_body "$BASE/api/v1/Account?select=name" "Acme Recipe Ltd" -H "Espo-Authorization: $auth"

    # 3. the console runs on the embedded PHP
    run_in ephpm espocrm config:get isInstalled | grep true >/dev/null \
        || { echo "!!! espocrm console not working" >&2; return 1; }
    echo "==> espocrm console works"

    compose down -v --remove-orphans
}

run_variant compose.yml
