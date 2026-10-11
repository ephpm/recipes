#!/usr/bin/env bash
# Smoke test: the entrypoint migrates and sets the admin password; we log in
# through the login form, open the homepage, the new-category form, the
# category tree and the parts list. Runs against the
# MariaDB compose file and Part-DB's native-SQLite single container (the
# ePHPm embedded-database variant is not shipped: see issues/shlink.md).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28206
recipe_init part-db

export ADMIN_PASSWORD="recipe-pass-123"
export DEFAULT_URI="$BASE/"

# Symfony CSRF tokens are rendered into the forms: pull one out of a page.
token() { grep -o "<input[^>]*name=\"$2\"[^>]*>" "$1" | head -n1 | sed 's/.*value="\([^"]*\)".*/\1/'; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # every page is locale-prefixed (/login -> /en/login)
    wait_http "$BASE/en/login" 200 300

    # 1. the entrypoint's migrations + admin password finished
    for _ in $(seq 1 90); do
        compose logs ephpm 2>/dev/null | grep "admin password set from ADMIN_PASSWORD" >/dev/null && break
        sleep 2
    done
    compose logs ephpm 2>/dev/null | grep "admin password set from ADMIN_PASSWORD" >/dev/null \
        || { echo "!!! install did not finish / admin password not set"; compose logs --tail=80 >&2; return 1; }

    # 2. real workflow: log in and open the homepage
    local jar page; jar="$(cookie_jar)"; page="$(native_path "$(mktemp)")"
    curl -s -c "$jar" -o "$page" "$BASE/en/login"
    # (Symfony 7.2+ stateless CSRF also checks Origin/Referer when no JS
    # cookie was set, so send both as a browser would)
    expect_status "$BASE/en/login" 302 -b "$jar" -c "$jar" -H "Origin: $BASE" -e "$BASE/en/login" \
        --data-urlencode "_csrf_token=$(token "$page" _csrf_token)" \
        --data "_username=admin&_password=$ADMIN_PASSWORD"
    expect_body "$BASE/en/" "Part-DB" -b "$jar" -c "$jar"

    # 3. the admin pages render for the logged-in admin: the new-category form
    #    and the category tree the sidebar loads (JSON)
    expect_body "$BASE/en/category/new" 'name="category_admin_form\[name\]"' -b "$jar" -c "$jar"
    expect_body "$BASE/en/tree/categories" '"text":"Categories"' -b "$jar" -c "$jar"
    expect_body "$BASE/en/parts" "Part-DB" -L -b "$jar" -c "$jar"

    # 4. the console runs on the embedded PHP
    # ("y" answers Part-DB's "running as root, continue? [no]" prompt)
    run_in ephpm sh -c "printf 'y\n' | SHELL_INTERACTIVE=1 partdb partdb:version" 2>/dev/null | grep -E "Part-DB|[0-9]+\.[0-9]+" >/dev/null \
        || { echo "!!! partdb console not working" >&2; return 1; }
    echo "==> partdb console works"

    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.sqlite.yml
