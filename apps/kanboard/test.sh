#!/usr/bin/env bash
# Smoke test: log in as the default admin, create a project through the web
# form, see it on the project list and through the JSON-RPC API, run the CLI
# cron job on the embedded PHP. Runs against the MariaDB compose file and
# Kanboard's own SQLite single container. (No ePHPm-embedded-database
# variant: Kanboard's MySQL driver runs `SET FOREIGN_KEY_CHECKS=0` around
# its migrations, which litewire forwards to SQLite — issues/kanboard.md.)
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28305
recipe_init kanboard

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # The login page. Kanboard runs its migrations on the first request, so
    # wait for the real form (with its CSRF token), not just a 200.
    wait_http "$BASE/?controller=AuthController&action=login" 200 180
    local jar csrf i=0
    jar="$(cookie_jar)"
    until csrf="$(form_value "$BASE/?controller=AuthController&action=login" csrf_token -c "$jar" -b "$jar" || true)"; [ -n "$csrf" ]; do
        i=$((i + 1))
        [ "$i" -lt 30 ] || { echo "!!! no csrf_token on the login page after 60s" >&2; compose logs --tail=40 ephpm >&2; return 1; }
        sleep 2
    done
    echo "==> login form is up (after $((i * 2))s)"

    # 1. real workflow: log in (admin / admin, form + CSRF token)
    expect_status "$BASE/?controller=AuthController&action=check" 302 -c "$jar" -b "$jar" \
        --data-urlencode "csrf_token=$csrf" --data "username=admin&password=admin"
    expect_body "$BASE/?controller=DashboardController&action=show" 'Dashboard' -b "$jar"

    # 2. create a project through the web form …
    csrf="$(form_value "$BASE/?controller=ProjectCreationController&action=create" csrf_token -c "$jar" -b "$jar")"
    [ -n "$csrf" ] || { echo "!!! no csrf_token on the project form" >&2; return 1; }
    expect_status "$BASE/?controller=ProjectCreationController&action=save" 302 -c "$jar" -b "$jar" \
        --data-urlencode "csrf_token=$csrf" --data-urlencode "name=ePHPm Recipe" --data "identifier=&per_swimlane_task_limits=0"
    expect_body "$BASE/?controller=ProjectListController&action=show" "ePHPm Recipe" -b "$jar"

    # 3. … and read it back through the JSON-RPC API (user credentials)
    expect_body "$BASE/jsonrpc.php" '"name":"ePHPm Recipe"' -u admin:admin \
        -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"getMyProjects","id":1}'

    # 4. the CLI runs on the embedded PHP (what the daily cron job calls)
    run_in ephpm ./cli cronjob >/dev/null
    run_in ephpm ./cli version | grep -E '[0-9]+\.[0-9]+' >/dev/null || { echo "!!! ./cli version failed" >&2; return 1; }
    echo "==> ./cli cronjob and ./cli version ran on the embedded PHP"

    # 5. the code-only paths are not served
    expect_status "$BASE/config.default.php" 403
    expect_status "$BASE/app/common.php" 403
    expect_status "$BASE/cli" 403

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.sqlite.yml
