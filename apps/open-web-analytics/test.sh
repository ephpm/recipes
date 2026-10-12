#!/usr/bin/env bash
# Smoke test: cli.php installs OWA on first start, the login page renders,
# log in through the form, add a tracked site through the admin form (nonce)
# and see it listed, send a page view to log.php the way owa.tracker.js does
# and read the stored request back from the database; the tracker script is
# served, the code and owa-config.php are not; the cron service's
# `cmd=schedule-run` works.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28614
recipe_init open-web-analytics
export OWA_PUBLIC_URL="$BASE/"
export OWA_ADMIN_PASSWORD="recipe-pass-123"

compose_up
wait_http "$BASE/index.php?do=base.loginForm" 200 300
# the base image's E2E fixtures (issues/joomla.md) must not be served
fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
expect_status "$BASE/" 302                                   # to the login form
expect_body "$BASE/index.php?do=base.loginForm" 'name="user_id"'
expect_status "$BASE/public/base/dist/owa.tracker.js" 200

# 1. log in
jar="$(cookie_jar)"
expect_status "$BASE/index.php" 302 -c "$jar" -b "$jar" \
    --data-urlencode "user_id=admin" --data-urlencode "password=$OWA_ADMIN_PASSWORD" --data-urlencode "action=base.login"
expect_body "$BASE/index.php?do=base.sitesProfile" 'name="nonce"' -b "$jar"
echo "==> logged in as admin"

# 2. add a tracked site through the admin form and see it listed
page="$(curl -s -b "$jar" "$BASE/index.php?do=base.sitesProfile")"
prop="$(printf '%s' "$page" | sed -n '/name="propertyId"/,/<\/select>/p' | grep -oE 'value="[^"]+"' | head -1 | cut -d'"' -f2)"
nonce="$(printf '%s' "$page" | sed -n 's/.*name="nonce" value="\([^"]*\)".*/\1/p' | head -1)"
[ -n "$prop" ] && [ -n "$nonce" ] || { echo "!!! no property / nonce on the site form" >&2; exit 1; }
expect_status "$BASE/index.php?do=base.sitesProfile" 302 -c "$jar" -b "$jar" \
    --data-urlencode "propertyId=$prop" --data-urlencode "name=recipe" --data-urlencode "streamType=web" \
    --data-urlencode "domain=https://recipe.example/" --data-urlencode "nonce=$nonce" --data-urlencode "action=base.sitesAdd"
site_id="$(run_in db mariadb -N -uowa -powa owa -e "SELECT site_id FROM owa_site WHERE domain = 'https://recipe.example/'" | tr -d '\r')"
[ -n "$site_id" ] || { echo "!!! the new site is not in owa_site" >&2; exit 1; }
# OWA names the profile itself ("Observation Profile <n>"); the second one is ours
expect_body "$BASE/index.php?do=base.sitesProfile" 'owa_siteControlItemName">Observation Profile 2<' -b "$jar"
echo "==> site $site_id added"
rm -f "$jar"

# 3. a page view through the tracking endpoint, stored and read back
expect_status "$BASE/log.php?owa_event_type=base.page_request&owa_site_id=$site_id&owa_page_url=https%3A%2F%2Frecipe.example%2Fhello&owa_page_title=Hello%20ePHPm&owa_timestamp=$(date +%s)" 200 \
    -A "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
i=0
until run_in db mariadb -N -uowa -powa owa -e "SELECT d.url FROM owa_request r JOIN owa_document d ON d.id = r.document_id WHERE r.site_id = '$site_id'" | grep 'recipe.example/hello' >/dev/null; do
    i=$((i + 1)); [ "$i" -ge 15 ] && { echo "!!! the page view was not stored" >&2; exit 1; }
    sleep 2
done
echo "==> page view stored for $site_id"

# 4. the CLI on the embedded PHP (what the cron service runs)
run_in ephpm owa-cli cmd=schedule-status >/dev/null || { echo "!!! cli.php cmd=schedule-status failed" >&2; exit 1; }
echo "==> cli.php cmd=schedule-status ran"

# 5. private paths
expect_status "$BASE/owa-config.php" 403
expect_status "$BASE/owa-data/owa-config.php" 403
expect_status "$BASE/Core/Lib.php" 403
expect_status "$BASE/vendor/autoload.php" 403
expect_status "$BASE/cli.php" 403
