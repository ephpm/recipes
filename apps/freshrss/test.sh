#!/usr/bin/env bash
# Smoke test: the container auto-installs FreshRSS and creates the admin user
# (FRESHRSS_INSTALL / FRESHRSS_USER, as the official image does), then we log
# in through the web form, create a category, read it back through the Fever
# API, and check the feed refresher and the KV-backed sessions. Runs against
# the PostgreSQL compose file and FreshRSS's own SQLite single container.
# (No ePHPm-embedded-database variant: FreshRSS's MySQL schema uses
# column-level CHARACTER SET/COLLATE, which litewire does not translate —
# issues/yourls.md has the repro.)
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28301
recipe_init freshrss

ADMIN_PASSWORD=recipe-pass-123
ADMIN_API_PASSWORD=recipe-api-456
export ADMIN_PASSWORD ADMIN_API_PASSWORD

# Scrape the CSRF token FreshRSS puts in every form (it is bound to the session).
csrf_token() { sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # / redirects to /i/ ; the login page answers 200 once the install has run.
    wait_http "$BASE/i/" 200 180
    # Belt and braces: wait for the login form proper, not just a 200 from /i/
    # (the installer page also answers 200 if the first-run setup is slow).
    local i=0
    until curl -s --max-time 10 "$BASE/i/?c=auth&a=login" | grep -q 'name="_csrf"'; do
        i=$((i + 1))
        [ "$i" -lt 60 ] || { echo "!!! login form did not appear within 120s" >&2; compose logs --tail=60 ephpm >&2; return 1; }
        sleep 2
    done
    echo "==> login form is up (after $((i * 2))s)"

    # 1. real workflow: log in through the web form. FreshRSS's form login is a
    #    bcrypt challenge: challenge = bcrypt(bcrypt(password, salt1) . nonce),
    #    which the browser computes in JS; we compute it with the embedded PHP.
    local jar csrf nonce_json salt1 nonce challenge
    jar="$(cookie_jar)"
    csrf="$(curl -s -c "$jar" -b "$jar" "$BASE/i/?c=auth&a=login" | csrf_token)"
    [ -n "$csrf" ] || { echo "!!! no CSRF token on the login page" >&2; return 1; }
    nonce_json="$(curl -s -c "$jar" -b "$jar" "$BASE/i/?c=javascript&a=nonce&user=admin")"
    salt1="$(printf '%s' "$nonce_json" | sed -n 's/.*"salt1":"\([^"]*\)".*/\1/p' | sed 's#\\/#/#g')"
    nonce="$(printf '%s' "$nonce_json" | sed -n 's/.*"nonce":"\([^"]*\)".*/\1/p')"
    [ -n "$salt1" ] && [ -n "$nonce" ] || { echo "!!! bad nonce response: $nonce_json" >&2; return 1; }
    challenge="$(run_in ephpm ephpm php -r 'echo password_hash(crypt($argv[1], $argv[2]) . $argv[3], PASSWORD_BCRYPT, ["cost" => 4]);' -- "$ADMIN_PASSWORD" "$salt1" "$nonce")"
    expect_status "$BASE/i/?c=auth&a=login" 302 -c "$jar" -b "$jar" \
        --data-urlencode "_csrf=$csrf" --data-urlencode "username=admin" \
        --data-urlencode "challenge=$challenge" --data "keep_logged_in=1"
    expect_body "$BASE/i/" 'c=subscription' -b "$jar"      # the reader UI, not the login form

    # 2. create a record: a category, through the subscription-management form
    csrf="$(curl -s -c "$jar" -b "$jar" "$BASE/i/?c=subscription" | csrf_token)"
    expect_status "$BASE/i/?c=category&a=create" 302 -c "$jar" -b "$jar" \
        --data-urlencode "_csrf=$csrf" --data-urlencode "new-category=ePHPm Recipe"
    expect_body "$BASE/i/?c=subscription" "ePHPm Recipe" -b "$jar"

    # 3. the Fever API (what mobile clients use) sees it: api_key = md5("user:api-password")
    local api_key
    api_key="$(printf 'admin:%s' "$ADMIN_API_PASSWORD" | md5sum | cut -d' ' -f1)"
    expect_body "$BASE/api/fever.php?api&groups" '"ePHPm Recipe"' --data "api_key=$api_key"

    # 4. FreshRSS's CLI scripts run on the embedded PHP (the `php` shim, via
    #    their #!/usr/bin/env php shebang) and reach the database
    run_in ephpm cli/list-users.php | grep '^admin$' >/dev/null || { echo "!!! list-users.php did not list admin" >&2; return 1; }
    run_in ephpm cli/user-info.php --header --user admin | grep 'admin' >/dev/null || { echo "!!! user-info.php failed" >&2; return 1; }
    echo "==> cli/list-users.php and cli/user-info.php ran on the embedded PHP"

    # 5. feed refresh (what CRON_MIN schedules) must *return*. On ePHPm v0.11.3
    #    the native dns_get_record() never does (issues/freshrss.md); the recipe's
    #    polyfill is what makes this finish. The default feeds are fetched from
    #    the internet, so only a hang (timeout exit 124) fails the test.
    local rc=0
    run_in ephpm timeout 120 php ./app/actualize_script.php >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 124 ] || { echo "!!! app/actualize_script.php hung for 120s" >&2; return 1; }
    echo "==> app/actualize_script.php returned (exit $rc) — feed refresh does not hang"

    # 6. the login session is in ePHPm's KV store (session.save_handler = ephpm)
    run_in ephpm ephpm kv keys 'session:*' | grep 'session:' >/dev/null \
        || { echo "!!! no PHP session in the KV store" >&2; return 1; }
    echo "==> PHP session stored in the KV store"

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.sqlite.yml
