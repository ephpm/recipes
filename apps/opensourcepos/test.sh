#!/usr/bin/env bash
# Smoke test: OSPOS migrates and provisions its secrets on start, the login
# page answers, the default admin logs in, a customer is created through the
# customer form (CSRF token) and found again through the customer search,
# and nothing above public/ is reachable.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28413
recipe_init opensourcepos
# OSPOS only answers for whitelisted Host headers (and builds its URLs from
# the matching entry).
export ALLOWED_HOSTNAMES="127.0.0.1:${PORT}"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/login" 200 240
    expect_status "$BASE/" 302

    # 1. log in as the seeded admin (the login form is CSRF-exempt upstream)
    local jar view tok date out
    jar="$(cookie_jar)"
    curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/login"
    expect_status "$BASE/login" 303 -c "$jar" -b "$jar" --data "username=admin&password=pointofsale"
    expect_body "$BASE/home" 'customers' -b "$jar" -c "$jar"

    # 2. create a customer through the customer form
    view="$(curl -s -b "$jar" -c "$jar" "$BASE/customers/view")"
    tok="$(printf '%s' "$view" | sed -nE 's/.*name="csrf_ospos_v4" value="([0-9a-f]+)".*/\1/p' | head -1)"
    date="$(printf '%s' "$view" | sed -nE 's/.*name="date" value="([^"]+)".*/\1/p' | head -1)"
    [ -n "$tok" ] && [ -n "$date" ] || { echo "!!! customer form has no CSRF token/date" >&2; return 1; }
    expect_body "$BASE/customers/save" '"success":true' -b "$jar" -c "$jar" \
        --data-urlencode "csrf_ospos_v4=$tok" --data-urlencode "date=$date" \
        --data "first_name=Hello&last_name=Ephpm&gender=1&email=hello%40example.com&phone_number=555-0100" \
        --data "address_1=&address_2=&city=Springfield&state=&zip=&country=&comments=Created+by+the+recipe+smoke+test" \
        --data "account_number=&company_name=&tax_id=&discount=&discount_type=0&employee_id=1&sales_tax_code_id="

    # 3. read it back through the customer search (the table's JSON feed)
    expect_body "$BASE/customers/search?search=Ephpm&order=asc&offset=0&limit=25&sort=last_name" \
        '"total":1' -b "$jar"
    expect_body "$BASE/customers/search?search=Ephpm&order=asc&offset=0&limit=25&sort=last_name" \
        'hello@example.com' -b "$jar"

    # 4. only public/ is served
    expect_status "$BASE/.env" 403
    expect_status "$BASE/app/Config/App.php" 404      # app/ is above public/: a route miss
    expect_body "$BASE/nope" "404" -H "Accept: text/html"   # CodeIgniter's 404 page (see the Dockerfile patch)
    expect_status "$BASE/info.php" 404

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
