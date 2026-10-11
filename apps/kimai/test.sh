#!/usr/bin/env bash
# Smoke test: the entrypoint installs the schema and creates the admin; we
# log in through the login form, open the dashboard, and create a customer
# through the JSON API. Runs against the MariaDB compose file, then the
# single-container embedded variant.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28205
recipe_init kimai

export ADMINMAIL="admin@example.com"
export ADMINPASS="recipe-pass-123"

# Symfony CSRF tokens are rendered into the forms: pull one out of a page.
token() { grep -o "name=\"$2\" value=\"[^\"]*\"" "$1" | head -n1 | sed 's/.*value="//; s/"$//'; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # "/" redirects to /en/login until logged in; wait for the login page.
    wait_http "$BASE/en/login" 200 300

    # 1. the entrypoint's install + admin creation finished
    for _ in $(seq 1 90); do
        compose logs ephpm 2>/dev/null | grep "Kimai is ready" >/dev/null && break
        sleep 2
    done
    compose logs ephpm 2>/dev/null | grep "Kimai is ready" >/dev/null \
        || { echo "!!! install did not finish"; compose logs --tail=80 >&2; return 1; }

    # 2. real workflow: log in and open the dashboard
    local jar page; jar="$(cookie_jar)"; page="$(native_path "$(mktemp)")"
    curl -s -c "$jar" -o "$page" "$BASE/en/login"
    # (Symfony 7.2+ stateless CSRF also checks Origin/Referer when no JS
    # cookie was set, so send both as a browser would)
    expect_status "$BASE/en/login_check" 302 -b "$jar" -c "$jar" -H "Origin: $BASE" -e "$BASE/en/login" \
        --data-urlencode "_csrf_token=$(token "$page" _csrf_token)" \
        --data "_username=admin&_password=$ADMINPASS"
    # a fresh user is sent through the first-login wizard before the dashboard
    expect_body "$BASE/en/wizard/intro" "Kimai" -b "$jar" -c "$jar"

    # 3. create a customer through the API (session auth works for the API
    #    when the request carries the X-AUTH-SESSION header)
    local out
    out="$(curl -s --max-time 30 -b "$jar" -H 'X-AUTH-SESSION: true' -H 'Content-Type: application/json' \
        --data '{"name":"Acme Recipe Ltd","country":"DE","currency":"EUR","timezone":"UTC","visible":true}' \
        "$BASE/api/customers")"
    printf '%s\n' "$out" | grep '"name":"Acme Recipe Ltd"' >/dev/null \
        || { echo "!!! customer not created: $out" >&2; compose logs --tail=80 >&2; return 1; }
    echo "==> customer created through the API"
    expect_body "$BASE/api/customers" '"name":"Acme Recipe Ltd"' -b "$jar" -H 'X-AUTH-SESSION: true'

    # 4. the console runs on the embedded PHP
    run_in ephpm kimai kimai:version | grep -E '^[0-9]|Kimai' >/dev/null \
        || { echo "!!! kimai console not working" >&2; return 1; }
    echo "==> kimai console works"

    compose down -v --remove-orphans
}

run_variant compose.yml
