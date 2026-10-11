#!/usr/bin/env bash
# Smoke test: install WordPress through the web installer, log in, publish a
# post with WP-CLI, and read it back on the front page. Runs against the
# MariaDB compose file, then the single-container embedded variant.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28010
recipe_init wordpress

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # (wp-login.php redirects to the installer until WordPress is installed)
    wait_http "$BASE/wp-admin/install.php" 200 180

    # 1. web installer (creates the tables)
    expect_status "$BASE/wp-admin/install.php?step=2" 200 \
        --data "weblog_title=ePHPm+Recipe&user_name=admin&admin_password=recipe-pass-123&admin_password2=recipe-pass-123&pw_weak=1&admin_email=admin%40example.com&blog_public=1&Submit=Install+WordPress&language="
    expect_body "$BASE/" "ePHPm Recipe"

    # 2. real workflow: log in and reach the dashboard
    local jar; jar="$(cookie_jar)"
    curl -s -o /dev/null -c "$jar" "$BASE/wp-login.php"
    expect_status "$BASE/wp-login.php" 302 -c "$jar" -b "$jar" \
        --data "log=admin&pwd=recipe-pass-123&wp-submit=Log+In&redirect_to=%2Fwp-admin%2F&testcookie=1"
    expect_body "$BASE/wp-admin/" "Dashboard" -b "$jar"
    rm -f "$jar"

    # 3. publish a post with WP-CLI (through the embedded PHP) and read it back
    run_in ephpm wp post create --post_title="Hello from ePHPm" --post_status=publish --porcelain
    expect_body "$BASE/" "Hello from ePHPm"

    # 4. the object cache is live in ePHPm's KV store (no Redis anywhere)
    run_in ephpm ephpm kv keys 'wp:*' | grep 'wp:' >/dev/null \
        || { echo "!!! object cache not populated"; return 1; }
    echo "==> object cache keys present in the KV store"

    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.embedded.yml
