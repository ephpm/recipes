#!/usr/bin/env bash
# Smoke test: the entrypoint runs `mautic:install` (schema + admin); we log
# in through the login form, create a contact through the form and find it. Runs
# against the MariaDB compose file (Mautic is MySQL/MariaDB only; Doctrine's
# MySQL DDL fails on the embedded database — issues/shlink.md).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28503
recipe_init mautic

export MAUTIC_SITE_URL="$BASE"
export MAUTIC_ADMIN_EMAIL="admin@example.com"
export MAUTIC_ADMIN_PASSWORD="Recipe-pass-123"

# Symfony CSRF tokens are rendered into the forms: pull one out of a page.
token() { grep -o "<input[^>]*name=\"$2\"[^>]*>" "$1" | head -n1 | sed 's/.*value="\([^"]*\)".*/\1/'; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/s/login" 200 600
    for _ in $(seq 1 120); do
        compose logs ephpm 2>/dev/null | grep "Mautic is ready" >/dev/null && break
        sleep 2
    done
    compose logs ephpm 2>/dev/null | grep "Mautic is ready" >/dev/null \
        || { echo "!!! install did not finish"; compose logs --tail=80 >&2; return 1; }

    # 1. real workflow: log in through the login form, open the dashboard
    local jar page; jar="$(cookie_jar)"; page="$(native_path "$(mktemp)")"
    curl -s -c "$jar" -o "$page" "$BASE/s/login"
    expect_status "$BASE/s/login_check" 302 -b "$jar" -c "$jar" -H "Origin: $BASE" -e "$BASE/s/login" \
        --data-urlencode "_csrf_token=$(token "$page" _csrf_token)" \
        --data "_username=admin&_password=$MAUTIC_ADMIN_PASSWORD"
    # the first dashboard visit after install redirects to itself once (it
    # creates the default widgets); the contact form below proves the session
    expect_status "$BASE/s/dashboard" 200 -L -b "$jar" -c "$jar"

    # 2. create a contact through the "New contact" form (no e-mail address:
    #    see the DNS note in the README) and find it in the contact list
    curl -s -b "$jar" -c "$jar" -o "$page" "$BASE/s/contacts/new"
    local tok loc
    tok="$(tr '\n' ' ' < "$page" | grep -oE '<input[^>]*name="lead\[_token\]"[^>]*>' | sed 's/.*value="\([^"]*\)".*/\1/')"
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 60 -b "$jar" -c "$jar" \
        -F "lead[_token]=$tok" -F "lead[firstname]=Ada" -F "lead[lastname]=Ephpmrecipe" \
        -F "lead[buttons][save]=" "$BASE/s/contacts/new")"
    case "$loc" in
        */s/contacts/view/*) echo "==> contact created -> $loc" ;;
        *) echo "!!! contact form redirected to '$loc'" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac
    expect_body "$loc" "Ephpmrecipe" -b "$jar" -c "$jar"
    expect_body "$BASE/s/contacts?search=Ephpmrecipe" "Ephpmrecipe" -b "$jar" -c "$jar"

    # 3. the console runs on the embedded PHP
    run_in ephpm mautic --version 2>/dev/null | grep -E "Mautic [0-9]+\.[0-9]+" >/dev/null \
        || { echo "!!! mautic console not working" >&2; return 1; }
    echo "==> mautic console works"

    compose down -v --remove-orphans
}

run_variant compose.yml
