#!/usr/bin/env bash
# Smoke test: the entrypoint runs `bagisto:install --no-interaction` (schema,
# seed data, default admin); the shop home page answers, the admin logs in
# through the login form and reaches the dashboard, and a customer account
# registered through the shop's sign-up form shows up in the admin's
# customer list. Runs against the MariaDB compose file.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28504
recipe_init bagisto
export BAGISTO_ADMIN_EMAIL="shopadmin@example.com"
export BAGISTO_ADMIN_PASSWORD="Recipe-pass-123"
export APP_URL="$BASE"

# csrf URL — GET the page (with the cookie jar) and print its CSRF token
csrf() {
    curl -s --max-time 30 -b "$jar" -c "$jar" "$1" \
        | grep -oE '<input[^>]*name="_token"[^>]*>' | sed -nE 's/.*value="([^"]+)".*/\1/p' | sed -n 1p
}

# post_redirect URL location-substring [curl args...] — POST and check where it redirects
post_redirect() {
    local url="$1" want="$2"; shift 2
    local loc
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 120 "$@" "$url" || true)"
    case "$loc" in
        *"$want"*) echo "==> $url -> $loc" ;;
        *) echo "!!! $url redirected to '$loc' (wanted *$want*)" >&2
           compose logs --tail=80 ephpm >&2 || true
           return 1 ;;
    esac
}

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # the installer runs before ePHPm starts listening
    wait_http "$BASE/" 200 900
    # scheduled commands run as `<phpBinary()> artisan ...`; that must work (issues/pterodactyl.md)
    run_in ephpm sh -c 'b="$(ephpm php -r "require \"vendor/autoload.php\"; echo Illuminate\Console\Application::phpBinary();")"; echo "phpBinary: $b"; eval "$b artisan --version"' || { echo "!!! <phpBinary> artisan does not run: scheduled commands would silently fail" >&2; exit 1; }
    expect_body "$BASE/" "Bagisto|bagisto"

    # 1. a customer signs up through the shop's registration form
    jar="$(cookie_jar)"
    local tok
    tok="$(csrf "$BASE/customer/register")"
    post_redirect "$BASE/customer/register" "/customer/login" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data-urlencode "first_name=Ada" --data-urlencode "last_name=Ephpmrecipe" \
        --data-urlencode "email=ada@example.com" \
        --data-urlencode "password=Recipe-pass-123" --data-urlencode "password_confirmation=Recipe-pass-123" \
        --data "is_subscribed=0&agreement=1"

    # 2. the admin logs in through the login form and finds that customer
    jar="$(cookie_jar)"
    tok="$(csrf "$BASE/admin/login")"
    post_redirect "$BASE/admin/login" "/admin/dashboard" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data-urlencode "email=$BAGISTO_ADMIN_EMAIL" --data-urlencode "password=$BAGISTO_ADMIN_PASSWORD"
    expect_status "$BASE/admin/dashboard" 200 -b "$jar" -c "$jar"
    # the customer datagrid is loaded over XHR as JSON
    expect_body "$BASE/admin/customers" "Ephpmrecipe" -b "$jar" -c "$jar" \
        -H "X-Requested-With: XMLHttpRequest" -H "Accept: application/json"

    # 3. artisan runs on the embedded PHP against the same database
    local out
    out="$(run_in ephpm ephpm php artisan migrate:status --no-ansi)"
    case "$out" in
        *Ran*) echo "==> artisan migrate:status reports migrations as run" ;;
        *) echo "!!! unexpected migrate:status output:" >&2; echo "$out" >&2; return 1 ;;
    esac

    compose down -v --remove-orphans
}

run_variant compose.yml
