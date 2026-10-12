#!/usr/bin/env bash
# Smoke test: the container installs MediaWiki through its CLI installer, then
# we log in through the API, create a page through the API, read it back on
# the web, and run a maintenance script on the embedded PHP. Runs against the
# MariaDB compose file and MediaWiki's own SQLite single container.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28309
recipe_init mediawiki

# Absolute URLs MediaWiki builds (and the API's loginreturnurl) must be ours.
export MEDIAWIKI_SITE_SERVER="$BASE"
export MEDIAWIKI_ADMIN_PASS="recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/index.php?title=Main_Page" 200 240      # after the CLI install
    # the base image's E2E fixtures (issues/joomla.md) must not be served
    fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
    expect_body "$BASE/index.php?title=Main_Page" 'MediaWiki has been installed'

    # 1. real workflow: log in through the API (login token, then clientlogin)
    local jar token
    jar="$(cookie_jar)"
    token="$(curl -s -c "$jar" -b "$jar" "$BASE/api.php?action=query&meta=tokens&type=login&format=json" \
        | sed -n 's/.*"logintoken":"\([^"]*\)".*/\1/p' | sed 's#\\\\#\\#g')"
    [ -n "$token" ] || { echo "!!! no login token from the API" >&2; return 1; }
    expect_body "$BASE/api.php" '"status":"PASS"' -c "$jar" -b "$jar" \
        --data-urlencode "logintoken=$token" --data-urlencode "loginreturnurl=$BASE/" \
        --data "action=clientlogin&username=admin&password=$MEDIAWIKI_ADMIN_PASS&format=json"

    # 2. create a page through the API (CSRF token), read it back on the web
    token="$(curl -s -c "$jar" -b "$jar" "$BASE/api.php?action=query&meta=tokens&format=json" \
        | sed -n 's/.*"csrftoken":"\([^"]*\)".*/\1/p' | sed 's#\\\\#\\#g')"
    [ -n "$token" ] || { echo "!!! no csrf token from the API" >&2; return 1; }
    expect_body "$BASE/api.php" '"result":"Success"' -c "$jar" -b "$jar" \
        --data-urlencode "token=$token" --data-urlencode "text=== Hello from ePHPm ==
A page created through the recipe smoke test." \
        --data "action=edit&title=EPHPm_Recipe&summary=created&format=json"
    expect_body "$BASE/index.php?title=EPHPm_Recipe" "Hello from ePHPm"
    expect_body "$BASE/index.php?title=Special:RecentChanges" "EPHPm Recipe"

    # 3. maintenance scripts run on the embedded PHP (and reach the database)
    run_in ephpm php maintenance/run.php Version | grep -E 'MediaWiki version: 1\.[0-9]+' >/dev/null \
        || { echo "!!! maintenance/run.php Version failed" >&2; return 1; }
    run_in ephpm php maintenance/run.php showSiteStats | grep -E 'Total pages' >/dev/null \
        || { echo "!!! maintenance/run.php showSiteStats failed" >&2; return 1; }
    echo "==> maintenance/run.php Version and showSiteStats ran on the embedded PHP"

    # 4. the config and code-only paths are not served
    expect_status "$BASE/LocalSettings.php" 403
    expect_status "$BASE/includes/Setup.php" 403

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.sqlite.yml
