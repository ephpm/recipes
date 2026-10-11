#!/usr/bin/env bash
# Smoke test: complete the web installer (the same POST the installer page's
# JavaScript sends), log in through the login endpoint, and open the backend
# calendar. Runs against the MariaDB compose file (the ePHPm embedded-database
# variant is not shipped: see issues/easyappointments.md).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28202
recipe_init easyappointments

export BASE_URL="$BASE"

# CodeIgniter's CSRF token: the value of the csrf_cookie cookie in the jar.
csrf() { awk '$6 == "csrf_cookie" { print $7 }' "$1" | tail -n1; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # "/" redirects to the installer (307) until the app is installed.
    wait_http "$BASE/index.php/installation" 200 240

    local jar; jar="$(cookie_jar)"
    curl -s -o /dev/null -c "$jar" "$BASE/index.php/installation"

    # 1. the installer: creates the schema, the admin, a sample service/provider
    expect_body "$BASE/index.php/installation/perform" '"success":\s*true' -b "$jar" -c "$jar" \
        --data-urlencode "csrf_token=$(csrf "$jar")" \
        --data "admin[first_name]=Recipe&admin[last_name]=Admin&admin[email]=admin%40example.com&admin[username]=admin&admin[password]=recipe-pass-123&admin[phone_number]=%2B1000&admin[language]=english" \
        --data "company[company_name]=ePHPm+Recipe&company[company_email]=info%40example.com&company[company_link]=http%3A%2F%2Fexample.com"
    expect_status "$BASE/index.php/installation" 307    # installed: redirects to the booking page
    expect_body "$BASE/" "ePHPm Recipe"                  # booking page shows the company name

    # 2. real workflow: log in (JSON endpoint) and open the backend calendar
    jar="$(cookie_jar)"
    curl -s -o /dev/null -c "$jar" "$BASE/index.php/login"
    expect_body "$BASE/index.php/login/validate" '"success":\s*true' -b "$jar" -c "$jar" \
        --data-urlencode "csrf_token=$(csrf "$jar")" \
        --data "username=admin&password=recipe-pass-123"
    expect_body "$BASE/index.php/calendar" "Easy!Appointments" -b "$jar"
    expect_status "$BASE/index.php/customers" 200 -b "$jar"

    compose down -v --remove-orphans
}

run_variant compose.yml
