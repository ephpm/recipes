#!/usr/bin/env bash
# Smoke test: the front end loads, the three backend endpoints answer the way
# the speed test worker uses them (download chunks from garbage.php, an upload
# POST to empty.php, getIP.php), a test result is stored through
# results/telemetry.php and read back on the password-protected stats page.
# Runs against the MariaDB compose file and the native SQLite variant.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28603
recipe_init librespeed
export PASSWORD="recipe-stats-pass"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 180
    expect_body "$BASE/" 'LibreSpeed'
    expect_body "$BASE/index-classic.html" 'speedtest.js'
    expect_status "$BASE/speedtest_worker.js" 200

    # 1. the backend, the way speedtest_worker.js calls it
    local size
    size="$(curl -s -o /dev/null -w '%{size_download}' --max-time 60 "$BASE/backend/garbage.php?r=0.1&ckSize=4")"
    [ "$size" = "4194304" ] || { echo "!!! garbage.php?ckSize=4 sent $size bytes (wanted 4194304)" >&2; return 1; }
    echo "==> backend/garbage.php?ckSize=4 -> $size bytes"
    # the recipe caps one response at GARBAGE_MAX_MB (32) and points the
    # clients at DL_CHUNK_MB (10): ePHPm buffers whole responses (README)
    size="$(curl -s -o /dev/null -w '%{size_download}' --max-time 60 "$BASE/backend/garbage.php?ckSize=1024")"
    [ "$size" = "33554432" ] || { echo "!!! garbage.php?ckSize=1024 sent $size bytes (wanted the 32 MiB cap)" >&2; return 1; }
    echo "==> backend/garbage.php?ckSize=1024 -> capped at $size bytes"
    expect_body "$BASE/settings.json" '"garbagePhp_chunkSize": 10'
    expect_body "$BASE/index-classic.html" 'setParameter\("garbagePhp_chunkSize", 10\)'
    head -c 4194304 /dev/zero > "$TMPBLOB"
    expect_status "$BASE/backend/empty.php?r=0.2" 200 --data-binary "@$(native_path "$TMPBLOB")" \
        -H 'Content-Type: application/octet-stream'
    expect_body "$BASE/backend/getIP.php?isp=true&distance=km&r=0.3" '"processedString"'

    # 2. real workflow: store a result through the telemetry endpoint …
    local out id jar
    out="$(curl -s --max-time 30 "$BASE/results/telemetry.php" -A 'ePHPm-recipe-test/1.0' \
        --data "ispinfo=%7B%7D&extra=recipe&dl=123.45&ul=67.89&ping=4.2&jitter=0.7&log=")"
    id="$(printf '%s' "$out" | sed -n 's/^id \(.*\)$/\1/p')"
    [ -n "$id" ] || { echo "!!! telemetry.php answered '$out'" >&2; compose logs --tail=40 >&2; return 1; }
    echo "==> results/telemetry.php stored test id $id"
    # … and read it back on the stats page after logging in
    jar="$(cookie_jar)"
    expect_body "$BASE/results/stats.php" 'name="password"' -c "$jar" -b "$jar"
    curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/results/stats.php?op=login" --data-urlencode "password=$PASSWORD"
    expect_body "$BASE/results/stats.php?op=id&id=$id" 'ePHPm-recipe-test/1.0' -c "$jar" -b "$jar"
    expect_body "$BASE/results/stats.php?op=id&id=$id" '123.45' -c "$jar" -b "$jar"

    # 3. the settings file executes (no source leak)
    size="$(curl -s -o /dev/null -w '%{size_download}' "$BASE/results/telemetry_settings.php")"
    [ "$size" = "0" ] || { echo "!!! results/telemetry_settings.php sent $size bytes" >&2; return 1; }
    echo "==> results/telemetry_settings.php runs as PHP (empty body)"

    rm -f "$jar"
    compose down -v --remove-orphans
}

TMPBLOB="$(mktemp)"
run_variant compose.yml
run_variant compose.sqlite.yml
rm -f "$TMPBLOB"
