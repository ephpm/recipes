#!/usr/bin/env bash
# Smoke test: the entrypoint migrates and generates the keys; we create the
# first user through the first-connection form, open the collections page,
# log out, log back in through the login form, and open the new-collection form.
# Runs against the PostgreSQL compose file and the MariaDB one (the ePHPm
# embedded-database variant is not shipped: see issues/shlink.md).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28207
recipe_init koillection

# Symfony CSRF tokens are rendered into the forms: pull one out of a page.
token() { grep -o "<input[^>]*name=\"$2\"[^>]*>" "$1" | head -n1 | sed 's/.*value="\([^"]*\)".*/\1/'; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # /login redirects to /first-connection while there is no user.
    wait_http "$BASE/first-connection" 200 300
    for _ in $(seq 1 90); do
        compose logs ephpm 2>/dev/null | grep "Koillection is ready" >/dev/null && break
        sleep 2
    done
    compose logs ephpm 2>/dev/null | grep "Koillection is ready" >/dev/null \
        || { echo "!!! setup did not finish"; compose logs --tail=80 >&2; return 1; }

    # 1. first user through the first-connection form (logs in afterwards)
    local jar page; jar="$(cookie_jar)"; page="$(native_path "$(mktemp)")"
    curl -s -c "$jar" -o "$page" "$BASE/first-connection"
    expect_status "$BASE/first-connection" 302 -b "$jar" -c "$jar" -H "Origin: $BASE" -e "$BASE/first-connection" \
        --data-urlencode "user[_token]=$(token "$page" 'user\[_token\]')" \
        --data "user[username]=admin&user[email]=admin%40example.com&user[plainPassword][first]=recipe-pass-123&user[plainPassword][second]=recipe-pass-123&user[timezone]=UTC&user[dateFormat]=Y-m-d"
    expect_body "$BASE/collections" "Koillection" -b "$jar" -c "$jar"

    # 2. real workflow: log out, log in through the login form, create a collection
    curl -s -o /dev/null -b "$jar" -c "$jar" "$BASE/logout"
    jar="$(cookie_jar)"
    # (the login form is the root page: SecurityController's route path is '')
    curl -s -c "$jar" -o "$page" "$BASE/"
    expect_status "$BASE/" 302 -b "$jar" -c "$jar" -H "Origin: $BASE" -e "$BASE/" \
        --data-urlencode "_csrf_token=$(token "$page" _csrf_token)" \
        --data "_login=admin&_password=recipe-pass-123"
    expect_body "$BASE/collections" "Koillection" -b "$jar" -c "$jar"
    expect_body "$BASE/collections/add" 'name="collection\[title\]"' -b "$jar" -c "$jar"   # the new-collection form renders

    # 3. the console runs on the embedded PHP
    run_in ephpm koillection about | grep -i "symfony" >/dev/null \
        || { echo "!!! koillection console not working" >&2; return 1; }
    echo "==> koillection console works"

    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.mariadb.yml
