#!/usr/bin/env bash
# Smoke test: the entrypoint writes .env and migrates; we finish the install
# wizard (create the super-admin), log in through the auth form, and open
# the admin dashboard and the public home page. Runs against the MariaDB
# compose file (Castopod is MySQL/MariaDB only, and Doctrine-free, but its
# CodeIgniter migrations use MySQL-only DDL: no embedded-database variant).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28209
recipe_init castopod

export CP_BASEURL="$BASE"

# CodeIgniter 4 session CSRF: the token is a hidden field (csrf_test_name)
# regenerated on every request, so each POST re-reads the page it submits.
token() { grep -o 'name="csrf_test_name" value="[^"]*"' "$1" | head -n1 | sed 's/.*value="//; s/"$//'; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/cp-install" 200 300
    for _ in $(seq 1 90); do
        compose logs ephpm 2>/dev/null | grep "Castopod is ready" >/dev/null && break
        sleep 2
    done

    # 1. the install wizard: .env is complete, so it goes straight to the super-admin form
    local jar page; jar="$(cookie_jar)"; page="$(native_path "$(mktemp)")"
    curl -s -c "$jar" -o "$page" "$BASE/cp-install"
    grep -q 'name="username"' "$page" || { echo "!!! install wizard did not reach the super-admin step"; head -c 1500 "$page"; compose logs --tail=60 ephpm >&2; return 1; }
    expect_status "$BASE/cp-install/create-superadmin" 303 -b "$jar" -c "$jar" -e "$BASE/cp-install" \
        --data-urlencode "csrf_test_name=$(token "$page")" \
        --data "username=admin&email=admin%40example.com&password=Recipe-pass-1234"

    # 2. real workflow: log in and open the admin dashboard
    curl -s -b "$jar" -c "$jar" -o "$page" "$BASE/cp-auth/login"
    expect_status "$BASE/cp-auth/login" 303 -b "$jar" -c "$jar" -e "$BASE/cp-auth/login" \
        --data-urlencode "csrf_test_name=$(token "$page")" \
        --data "email=admin%40example.com&password=Recipe-pass-1234"
    expect_body "$BASE/cp-admin" "admin" -b "$jar" -c "$jar"
    expect_status "$BASE/cp-admin/podcasts/new" 200 -b "$jar" -c "$jar"

    # 3. the public site and the console
    expect_status "$BASE/" 200
    run_in ephpm spark list 2>/dev/null | grep "castopod:" >/dev/null \
        || { echo "!!! spark console not working" >&2; return 1; }
    echo "==> spark console works"

    compose down -v --remove-orphans
}

run_variant compose.yml
