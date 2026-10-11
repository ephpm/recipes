#!/usr/bin/env bash
# Smoke test: register the first user through the registration form, log
# in through the login form, add a subscription through the app's endpoint
# (what its form posts), read it back on the home page, and run one of the
# cron scripts inside the cron service.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28107
recipe_init wallos

# expect_redirect URL location-substring [curl args...] — request and check where it redirects
expect_redirect() {
    local url="$1" want="$2"; shift 2
    local loc
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 60 "$@" "$url" || true)"
    case "$loc" in
        *"$want"*) echo "==> $url -> $loc" ;;
        *) echo "!!! $url redirected to '$loc' (wanted *$want*)" >&2
           compose logs --tail=80 >&2 || true
           return 1 ;;
    esac
}

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # with no user yet, the login page sends you to the registration form
    wait_http "$BASE/registration.php" 200 180
    expect_redirect "$BASE/login.php" "registration.php"

    # 1. register the first user (becomes the admin)
    local jar; jar="$(cookie_jar)"
    expect_redirect "$BASE/registration.php" "login.php?registered=true" -b "$jar" -c "$jar" \
        --data "username=admin&firstname=Admin&lastname=User&email=admin%40example.com&password=recipe-pass-123&confirm_password=recipe-pass-123&main_currency=USD&language=en"

    # 2. real workflow: log in through the login form
    expect_redirect "$BASE/login.php" "$BASE" -b "$jar" -c "$jar" \
        --data "username=admin&password=recipe-pass-123"
    # a logged-in user is sent from the front page to the subscriptions page
    expect_redirect "$BASE/index.php" "subscriptions.php" -b "$jar" -c "$jar"
    expect_body "$BASE/subscriptions.php" "admin" -b "$jar" -c "$jar"

    # 3. add a subscription (the add form posts to this endpoint, with the
    #    CSRF token the page embeds as window.csrfToken) and read it back
    local tok out
    tok="$(curl -s --max-time 30 -b "$jar" -c "$jar" "$BASE/subscriptions.php" \
        | sed -nE 's/.*window\.csrfToken = "([^"]+)".*/\1/p' | sed -n 1p)"
    [ -n "$tok" ] || { echo "!!! no CSRF token on the subscriptions page" >&2; return 1; }
    out="$(curl -s --max-time 60 -b "$jar" -c "$jar" \
        --data-urlencode "csrf_token=$tok" \
        --data-urlencode "name=Hello from ePHPm" \
        --data "price=9.99&currency_id=1&frequency=1&cycle=3&next_payment=2027-01-01&start_date=2026-10-11&payment_method_id=1&payer_user_id=1&category_id=1&notes=&url=&logo-url=&notify_days_before=0&replacement_subscription_id=0" \
        "$BASE/endpoints/subscription/add.php")"
    case "$out" in
        *'"status":"Success"'*) echo "==> subscription added" ;;
        *) echo "!!! add.php did not succeed: $out" >&2; compose logs --tail=80 ephpm >&2; return 1 ;;
    esac
    expect_body "$BASE/subscriptions.php" "Hello from ePHPm" -b "$jar" -c "$jar"

    # 4. a cron script runs inside the cron service against the same database
    run_in cron sh -c 'cd /var/www/html && ephpm php endpoints/cronjobs/updatenextpayment.php' \
        || { echo "!!! updatenextpayment.php failed in the cron service" >&2; return 1; }
    echo "==> cron service ran updatenextpayment.php"

    compose down -v --remove-orphans
}

run_variant compose.yml
