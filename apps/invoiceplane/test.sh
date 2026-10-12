#!/usr/bin/env bash
# Smoke test: the entrypoint installs the schema and creates the admin; we
# log in through the web form, reach the dashboard, and create a client
# through the HTML form. Runs against the MariaDB compose file (the ePHPm
# embedded-database variant is not shipped: see issues/invoiceplane.md).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28201
recipe_init invoiceplane

export IP_URL="$BASE"
export DEFAULT_ADMIN_EMAIL="admin@example.com"
export DEFAULT_ADMIN_PASSWORD="recipe-pass-123"

# CodeIgniter's CSRF token: the value of the ip_csrf_cookie cookie in the jar.
csrf() { awk '$6 == "ip_csrf_cookie" { print $7 }' "$1" | tail -n1; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # "/" redirects to the login page (302); wait for the login page itself.
    wait_http "$BASE/sessions/login" 200 240
    # the base image's E2E fixtures (issues/joomla.md) must not be served
    fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac

    # 1. the entrypoint's migration + default user finished
    for _ in $(seq 1 60); do
        compose logs ephpm 2>/dev/null | grep "Default admin user created" >/dev/null && break
        sleep 2
    done
    compose logs ephpm 2>/dev/null | grep "Default admin user created" >/dev/null \
        || { echo "!!! default admin not created"; compose logs --tail=80 >&2; return 1; }

    # 2. real workflow: log in and reach the dashboard
    local jar; jar="$(cookie_jar)"
    curl -s -o /dev/null -c "$jar" "$BASE/sessions/login"
    # (CodeIgniter answers a POST with 303; a failed login also redirects, so
    # the dashboard check below is the real assertion)
    expect_status "$BASE/sessions/login" 303 -c "$jar" -b "$jar" \
        --data-urlencode "_ip_csrf=$(csrf "$jar")" \
        --data-urlencode "email=$DEFAULT_ADMIN_EMAIL" \
        --data-urlencode "password=$DEFAULT_ADMIN_PASSWORD" \
        --data "btn_login=true"
    expect_body "$BASE/dashboard" "Dashboard" -b "$jar" -c "$jar"

    # 3. create a client through the form, then read it back from the list
    curl -s -o /dev/null -b "$jar" -c "$jar" "$BASE/clients/form"
    expect_status "$BASE/clients/form" 303 -b "$jar" -c "$jar" \
        --data-urlencode "_ip_csrf=$(csrf "$jar")" \
        --data "is_update=0&client_active=1&client_title=&client_name=Acme+Recipe+Ltd&client_language=system&btn_submit=1"
    expect_body "$BASE/clients/status/active" "Acme Recipe Ltd" -b "$jar"
    rm -f "$jar"

    compose down -v --remove-orphans
}

run_variant compose.yml
