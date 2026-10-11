#!/usr/bin/env bash
# Smoke test: run YOURLS's installer, log in to the admin, read the API
# signature token from the Tools page, shorten a URL through the API, follow
# the short link, and read its click count back. MariaDB compose file only:
# YOURLS's schema uses column-level CHARACTER SET / COLLATE, which ePHPm's
# embedded database does not accept (issues/yourls.md).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28303
recipe_init yourls

# Short links are built from YOURLS_SITE, and the login cookie is scoped to
# its host — so it must be the address the test talks to.
export YOURLS_SITE="$BASE"
export YOURLS_PASS="recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/admin/install.php" 200 180

    # 1. installer (creates the tables)
    expect_body "$BASE/admin/install.php" "successfully" --data "install=Install+YOURLS"

    # 2. real workflow: log in to the admin (form + nonce)
    local jar nonce
    jar="$(cookie_jar)"
    nonce="$(curl -s -c "$jar" -b "$jar" "$BASE/admin/" | sed -n 's/.*name="nonce" value="\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$nonce" ] || { echo "!!! no login nonce on /admin/" >&2; return 1; }
    # (YOURLS redirects with 301 after a successful login — yourls_redirect()'s default)
    expect_status "$BASE/admin/" 301 -c "$jar" -b "$jar" \
        --data-urlencode "username=admin" --data-urlencode "password=$YOURLS_PASS" --data-urlencode "nonce=$nonce"
    expect_body "$BASE/admin/" 'action=logout' -b "$jar"           # logged in: the logout link is there

    # 3. the API, with the signature token shown on the Tools page
    local token
    token="$(curl -s -b "$jar" "$BASE/admin/tools.php" | sed -n 's/.*signature token: <strong><code>\([0-9a-f]*\)<\/code>.*/\1/p' | head -1)"
    [ -n "$token" ] || { echo "!!! no signature token on /admin/tools.php" >&2; return 1; }
    expect_body "$BASE/yourls-api.php" '"status":"success"' \
        --data "signature=$token&action=shorturl&url=https%3A%2F%2Fephpm.dev%2F&keyword=ephpm&title=ePHPm&format=json"

    # 4. the short link resolves (yourls-loader.php via [server] fallback) …
    local location
    location="$(curl -s -o /dev/null -w '%{redirect_url}' "$BASE/ephpm")"
    [ "$location" = "https://ephpm.dev/" ] || { echo "!!! /ephpm redirected to '$location'" >&2; return 1; }
    echo "==> $BASE/ephpm -> https://ephpm.dev/"
    # … and the click was counted
    expect_body "$BASE/yourls-api.php" '"clicks":"?1"?' \
        --data "signature=$token&action=url-stats&shorturl=ephpm&format=json"

    # 5. the code-only paths are not served
    expect_status "$BASE/user/config.php" 403
    expect_status "$BASE/includes/load-yourls.php" 403

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
