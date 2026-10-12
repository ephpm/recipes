#!/usr/bin/env bash
# Smoke test: elgg-cli installs on first start, the home page renders, the
# simplecache serves CSS through index.php, log in through the form (CSRF
# token + timestamp), add a bookmark through the bookmarks form and read it
# back on its page, run elgg-cli cron; settings.php and the code are not served.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28613
recipe_init elgg
export ELGG_WWWROOT="$BASE/"
export ELGG_ADMIN_PASSWORD="recipe-pass-1234567"     # Elgg 7: 16 characters minimum

compose_up
wait_http "$BASE/" 200 300
# the base image's E2E fixtures (issues/joomla.md) must not be served
fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
expect_body "$BASE/" 'Elgg on ePHPm'
css="$(curl -s "$BASE/" | grep -oE "$BASE/cache/[0-9]+/default/[a-z/]*elgg\.css" | head -1)"
[ -n "$css" ] || { echo "!!! no simplecache CSS link on the home page" >&2; exit 1; }
expect_body "$css" '\.elgg-'

jar="$(cookie_jar)"
# fetch_form URL — one GET; sets $token/$ts (a matching pair) and $page
fetch_form() {
    page="$(curl -s -c "$jar" -b "$jar" "$1")"
    token="$(printf '%s' "$page" | sed -n 's/.*name="__elgg_token" value="\([^"]*\)".*/\1/p' | head -1)"
    ts="$(printf '%s' "$page" | sed -n 's/.*name="__elgg_ts" value="\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$token" ] && [ -n "$ts" ] || { echo "!!! no CSRF token on $1" >&2; exit 1; }
}

# 1. log in
fetch_form "$BASE/login"
code="$(curl -s -o /dev/null -w '%{http_code}' -c "$jar" -b "$jar" \
    --data-urlencode "__elgg_token=$token" --data-urlencode "__elgg_ts=$ts" \
    --data-urlencode "username=admin" --data-urlencode "password=$ELGG_ADMIN_PASSWORD" "$BASE/action/login")"
[ "$code" = 302 ] || { echo "!!! login answered $code" >&2; exit 1; }
expect_body "$BASE/admin" '<title>Dashboard' -b "$jar"
echo "==> logged in as admin"

# 2. add a bookmark through its form and read it back
add_url="$(curl -s -b "$jar" "$BASE/bookmarks/all" | grep -oE "$BASE/bookmarks/add/[0-9]+" | head -1)"
[ -n "$add_url" ] || { echo "!!! no 'Add bookmark' link" >&2; exit 1; }
fetch_form "$add_url"
container="$(printf '%s' "$page" | sed -n 's/.*name="container_guid" value="\([^"]*\)".*/\1/p' | head -1)"
curl -s -o /dev/null -c "$jar" -b "$jar" \
    --data-urlencode "__elgg_token=$token" --data-urlencode "__elgg_ts=$ts" \
    --data-urlencode "title=ePHPm recipe bookmark" --data-urlencode "address=https://ephpm.dev/" \
    --data-urlencode "description=added by the smoke test" --data-urlencode "tags=ephpm" \
    --data-urlencode "access_id=2" --data-urlencode "container_guid=${container:-${add_url##*/}}" \
    "$BASE/action/bookmarks/edit"
expect_body "$BASE/bookmarks/all" 'ePHPm recipe bookmark' -b "$jar"
view="$(curl -s -b "$jar" "$BASE/bookmarks/all" | grep -oE "$BASE/bookmarks/view/[0-9]+/[a-z0-9-]+" | head -1)"
[ -n "$view" ] || { echo "!!! no bookmark view link" >&2; exit 1; }
expect_body "$view" 'https://ephpm.dev/' -b "$jar"
echo "==> bookmark created and read back"
rm -f "$jar"

# 3. elgg-cli on the embedded PHP
run_in ephpm elgg-cli cron -i minute --no-ansi | grep -i 'minute' >/dev/null \
    || { echo "!!! elgg-cli cron failed" >&2; exit 1; }
echo "==> elgg-cli cron ran"

# 4. private paths
expect_status "$BASE/elgg-config/settings.php" 403
expect_status "$BASE/vendor/autoload.php" 403
expect_status "$BASE/install.php" 403
