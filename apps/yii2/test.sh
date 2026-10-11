#!/usr/bin/env bash
# Smoke test: the home page renders, `yii migrate` ran against the database,
# a missing route gets Yii's 404 page, and the admin logs in through the
# CSRF-protected login form. MariaDB only: the embedded database cannot run
# `yii migrate` (issues/yii2.md).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28401
recipe_init yii2

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 180
    expect_body "$BASE/" "My Yii Application"
    expect_status "$BASE/site/no-such-page" 404     # Yii error page, not a bare 500 (silentExitOnException)

    # the migration table exists (entrypoint ran `yii migrate`)
    local i=0
    until run_in ephpm ephpm php yii migrate/history --interactive=0 2>/dev/null | grep -E "No migration|m[0-9]{6}_" >/dev/null; do
        i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! migrations not applied"; compose logs --tail=60 ephpm; return 1; }
        sleep 2
    done
    echo "==> yii migrate ran against the database"

    local jar tok; jar="$(cookie_jar)"
    tok="$(form_value "$BASE/site/login" "_csrf" -c "$jar" -b "$jar")"
    [ -n "$tok" ] || { echo "!!! no CSRF token on the login form"; return 1; }
    expect_status "$BASE/site/login" 302 -c "$jar" -b "$jar" \
        --data-urlencode "_csrf=$tok" --data-urlencode "LoginForm[username]=admin" \
        --data-urlencode "LoginForm[password]=admin" --data-urlencode "LoginForm[rememberMe]=0"
    expect_body "$BASE/" "Logout \(admin\)" -b "$jar"
    expect_status "$BASE/site/login" 400 --data-urlencode "LoginForm[username]=admin"   # no CSRF token
    rm -f "$jar"
    echo "==> logged in as admin"

    compose down -v --remove-orphans
}

run_variant compose.yml
