#!/usr/bin/env bash
# Smoke test: selfoss answers (page + its JS bundle from public/), the
# configured user logs in, a feed source is added (an RSS file served by the
# same ePHPm), the updater service's cliupdate.php fetches it, the item is
# read back through the JSON API, and config/database/code are not served.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28417
recipe_init selfoss
export SELFOSS_PLAIN_PASSWORD="recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 120
    local js
    js="$(curl -s "$BASE/" | grep -oE 'src="index\.[0-9a-f]+\.js"' | head -1 | sed 's/src="//; s/"//')"
    [ -n "$js" ] || { echo "!!! no JS bundle referenced on /" >&2; return 1; }
    expect_status "$BASE/$js" 200                    # public/ via the fallback chain
    expect_body "$BASE/api/about" '"version":"2.19"'

    # a feed to subscribe to, served by this same ePHPm (reachable as
    # http://ephpm:8080 from both containers)
    run_in ephpm sh -c 'cat > /app/public/recipe-feed.xml' <<'XML'
<?xml version="1.0"?>
<rss version="2.0"><channel><title>Recipe feed</title><link>http://example.com/</link><description>x</description>
<item><title>Hello from ePHPm</title><link>http://example.com/1</link><guid>recipe-1</guid><description>Item body</description><pubDate>Sun, 11 Oct 2026 12:00:00 +0000</pubDate></item>
</channel></rss>
XML

    # 1. log in
    local jar
    jar="$(cookie_jar)"
    expect_body "$BASE/login" '"success":true' -c "$jar" -b "$jar" -H 'Accept: application/json' \
        --data-urlencode "username=admin" --data-urlencode "password=$SELFOSS_PLAIN_PASSWORD"

    # 2. add the source
    expect_body "$BASE/source" '"success":true' -b "$jar" -H 'Accept: application/json' \
        --data-urlencode "title=Recipe feed" --data-urlencode 'spout=spouts\rss\feed' \
        --data-urlencode "url=http://ephpm:8080/recipe-feed.xml" --data-urlencode "tags[]=recipes"
    expect_body "$BASE/sources/list" '"title":"Recipe feed"' -b "$jar" -H 'Accept: application/json'

    # 3. the updater container's job fetches it …
    run_in updater php cliupdate.php
    # … and the item is there
    expect_body "$BASE/items?type=newest" '"title":"Hello from ePHPm"' -b "$jar" -H 'Accept: application/json'
    compose logs updater | grep -q 'refreshing feeds every' || { echo "!!! updater loop not running" >&2; return 1; }

    # 4. private paths
    expect_status "$BASE/config-example.ini" 403
    expect_status "$BASE/data/sqlite/selfoss.db" 403
    expect_status "$BASE/src/constants.php" 403
    expect_status "$BASE/info.php" 404               # no ePHPm test fixtures (the app is in /app)
    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
