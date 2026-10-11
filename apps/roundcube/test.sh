#!/usr/bin/env bash
# Smoke test: log in through Roundcube's form against the stack's test IMAP
# server (GreenMail), open the mailbox, save a contact through the address
# book and read it back as a vCard export, run a bin/ script on the embedded
# PHP. Runs against the MariaDB compose file and the SQLite variant.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28602
recipe_init roundcube

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 180
    expect_body "$BASE/" 'name="_user"'                       # the login form
    expect_status "$BASE/static.php/skins/elastic/styles/styles.min.css" 200   # assets via static.php

    # 1. real workflow: log in (form + session token); GreenMail accepts any user
    local jar token
    jar="$(cookie_jar)"
    token="$(form_value "$BASE/?_task=login" _token -c "$jar" -b "$jar")"
    [ -n "$token" ] || { echo "!!! no _token on the login form" >&2; return 1; }
    expect_status "$BASE/?_task=login" 302 -c "$jar" -b "$jar" \
        --data-urlencode "_token=$token" \
        --data "_task=login&_action=login&_timezone=UTC&_url=&_user=alice%40example.com&_pass=recipe-pass-123"
    expect_body "$BASE/?_task=mail&_mbox=INBOX" 'alice@example.com' -b "$jar"    # logged in, mailbox open

    # 2. create a record: a contact in the personal address book …
    token="$(form_value "$BASE/?_task=addressbook" _token -c "$jar" -b "$jar" || true)"
    [ -n "$token" ] || token="$(curl -s -b "$jar" "$BASE/?_task=addressbook" | sed -n 's/.*"request_token":"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$token" ] || { echo "!!! no request token on the address book page" >&2; return 1; }
    curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/?_task=addressbook&_action=save" \
        --data-urlencode "_token=$token" --data-urlencode "_name=ePHPm Recipe" \
        --data "_source=0&_gid=&_email%5B%5D=hello%40ephpm.dev&_subtype_email%5B%5D=home"
    # … and read it back as a vCard export (the export action wants the request token too)
    expect_body "$BASE/?_task=addressbook&_action=export&_source=0&_token=$token" 'FN:ePHPm Recipe' -b "$jar"

    # 3. Roundcube's CLI scripts run on the embedded PHP (the `php` shim)
    run_in ephpm bin/cleandb.sh >/dev/null || { echo "!!! bin/cleandb.sh failed" >&2; return 1; }
    echo "==> bin/cleandb.sh ran on the embedded PHP"

    # 4. nothing outside public_html/ is reachable
    expect_status "$BASE/config/config.inc.php" 404
    expect_status "$BASE/program/include/rcmail.php" 404
    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.sqlite.yml
