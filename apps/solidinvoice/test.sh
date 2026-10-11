#!/usr/bin/env bash
# Smoke test: the entrypoint runs SolidInvoice's installer (schema + admin);
# we log in through the login form, create the first company through the
# onboarding form and read it back. Runs against the MariaDB compose file
# (SolidInvoice is MySQL-family only; Doctrine's MySQL DDL fails on the
# embedded database — issues/shlink.md).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28501
recipe_init solidinvoice

export APPLICATION_URL="$BASE"
export ADMIN_EMAIL="admin@example.com"
export ADMIN_PASSWORD="recipe-pass-123"

# Symfony CSRF tokens are rendered into the forms: pull one out of a page.
token() { grep -o "<input[^>]*name=\"$2\"[^>]*>" "$1" | head -n1 | sed 's/.*value="\([^"]*\)".*/\1/'; }
# The URL a page's first <form> posts to.
form_action() { grep -o '<form[^>]* action="[^"]*"' "$1" | head -n1 | sed 's/.*action="//; s/"$//'; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/login" 200 300
    for _ in $(seq 1 90); do
        compose logs ephpm 2>/dev/null | grep "SolidInvoice is ready" >/dev/null && break
        sleep 2
    done
    compose logs ephpm 2>/dev/null | grep "SolidInvoice is ready" >/dev/null \
        || { echo "!!! install did not finish"; compose logs --tail=80 >&2; return 1; }
    run_in ephpm solidinvoice solidinvoice:is-installed >/dev/null \
        || { echo "!!! solidinvoice:is-installed says not installed" >&2; compose logs --tail=60 ephpm >&2; return 1; }
    echo "==> installed"

    # 1. real workflow: log in through the login form
    local jar page action; jar="$(cookie_jar)"; page="$(native_path "$(mktemp)")"
    curl -s -c "$jar" -o "$page" "$BASE/login"
    action="$(form_action "$page")"; action="${action:-/login}"
    case "$action" in http*) ;; *) action="$BASE$action" ;; esac
    local loc
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 30 -b "$jar" -c "$jar" \
        -H "Origin: $BASE" -e "$BASE/login" \
        --data-urlencode "_csrf_token=$(token "$page" _csrf_token)" \
        --data-urlencode "_username=$ADMIN_EMAIL" --data-urlencode "_password=$ADMIN_PASSWORD" "$action")"
    case "$loc" in
        */login|"") echo "!!! login failed (redirected to '$loc')" >&2; return 1 ;;
        *) echo "==> logged in (-> $loc)" ;;
    esac

    # 2. a fresh install has no company yet: login lands on onboarding,
    #    which sends you to /create-company. Create one through the form (a
    #    real record) and read it back on the dashboard.
    curl -s -b "$jar" -c "$jar" -o "$page" "$BASE/create-company"
    expect_status "$BASE/create-company" 302 -b "$jar" -c "$jar" \
        --data-urlencode "company[_token]=$(token "$page" 'company\[_token\]')" \
        --data-urlencode "company[name]=Recipe Test Co" --data-urlencode "company[currency]=USD"
    expect_body "$BASE/dashboard" "Recipe Test Co" -b "$jar" -c "$jar"
    # with a company selected the client list renders instead of redirecting
    expect_status "$BASE/clients/" 200 -b "$jar" -c "$jar"

    # 3. the console runs on the embedded PHP
    run_in ephpm solidinvoice about | grep -i "symfony" >/dev/null \
        || { echo "!!! solidinvoice console not working" >&2; return 1; }
    echo "==> solidinvoice console works"

    compose down -v --remove-orphans
}

run_variant compose.yml
