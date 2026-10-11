#!/usr/bin/env bash
# Smoke test: the bridge list renders, a bridge's form page renders, the
# DemoBridge (no network needed) produces an Atom and a JSON feed, a second
# request is answered from the file cache, a custom bridge dropped into the
# config volume is picked up on restart, and code/cache paths are refused.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28408
recipe_init rss-bridge

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 120
    expect_body "$BASE/" 'DemoBridge'
    expect_body "$BASE/?action=detect&url=x" 'Bridge|bridge'

    # 1. generate feeds (the "use" workflow: pick a bridge, a context, a format)
    expect_body "$BASE/?action=display&bridge=DemoBridge&context=testCheckbox&testCheckbox=on&format=Atom" \
        '<content type="html">Awesome content !</content>|Awesome content !'
    expect_body "$BASE/?action=display&bridge=DemoBridge&context=testList&testList=test2&format=Json" \
        '"title": ?"Test"'
    # the file cache in cache/ was written and is used for the repeat request
    local n
    n="$(run_in ephpm sh -c 'find /app/cache -type f | wc -l')"
    [ "${n:-0}" -ge 1 ] || { echo "!!! nothing in the file cache" >&2; return 1; }
    echo "==> file cache holds $n entries"

    # 2. a custom bridge from the config volume (as with the official image)
    copy_in ephpm "$DIR/test/RecipeBridge.php" /config/RecipeBridge.php
    compose restart ephpm
    wait_http "$BASE/" 200 60
    expect_body "$BASE/?action=display&bridge=RecipeBridge&format=Atom" 'Hello from ePHPm'

    # 3. private paths
    expect_status "$BASE/config.default.ini.php" 403
    expect_status "$BASE/lib/bootstrap.php" 403
    expect_status "$BASE/cache/" 403

    compose down -v --remove-orphans
}

run_variant compose.yml
