#!/usr/bin/env bash
# Smoke test: the entrypoint installs the schema and the default admin; we
# log in through the login form, open the unread list, save an article
# through the "new entry" form and read it back. Runs against the MariaDB
# compose file, wallabag's native-SQLite single container, then the ePHPm
# embedded-database variant.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28204
recipe_init wallabag

export SYMFONY__ENV__DOMAIN_NAME="$BASE"

# Symfony CSRF tokens are rendered into the forms: pull one out of a page.
token() { grep -o "name=\"$2\" value=\"[^\"]*\"" "$1" | head -n1 | sed 's/.*value="//; s/"$//'; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/login" 200 300
    expect_body "$BASE/api/info" '"appname":\s*"wallabag"'

    # 1. the entrypoint's install (schema + default admin) finished
    for _ in $(seq 1 90); do
        compose logs ephpm 2>/dev/null | grep "wallabag is ready" >/dev/null && break
        sleep 2
    done
    compose logs ephpm 2>/dev/null | grep "wallabag is ready" >/dev/null \
        || { echo "!!! install did not finish"; compose logs --tail=80 >&2; return 1; }

    # 2. real workflow: log in as the default admin
    local jar page; jar="$(cookie_jar)"; page="$(native_path "$(mktemp)")"
    curl -s -c "$jar" -o "$page" "$BASE/login"
    expect_status "$BASE/login_check" 302 -b "$jar" -c "$jar" \
        --data-urlencode "_csrf_token=$(token "$page" _csrf_token)" \
        --data "_username=wallabag&_password=wallabag"
    # (an empty account is sent to the quickstart page first)
    expect_body "$BASE/quickstart" "wallabag" -b "$jar" -c "$jar"

    # 3. save an article (the app fetches it; the fetch target is the app's
    #    own login page, so no internet is needed)
    curl -s -b "$jar" -c "$jar" -o "$page" "$BASE/new-entry"
    expect_status "$BASE/new-entry" 302 -b "$jar" -c "$jar" \
        --data-urlencode "entry[_token]=$(token "$page" 'entry\[_token\]')" \
        --data-urlencode "entry[url]=http://127.0.0.1:8080/login"
    expect_body "$BASE/unread/list" "127.0.0.1:8080" -b "$jar" -c "$jar"

    # 4. the console runs on the embedded PHP
    run_in ephpm wallabag wallabag:user:list 2>/dev/null | grep wallabag >/dev/null \
        || { echo "!!! console cannot list users" >&2; return 1; }
    echo "==> wallabag console lists the admin user"

    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.sqlite.yml
