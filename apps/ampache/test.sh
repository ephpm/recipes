#!/usr/bin/env bash
# Smoke test: Ampache installs from the CLI on the first start, the admin
# logs in through the login form, a music catalog is created and scanned
# with the bundled CLI (one generated WAV file), the song is found and
# streamed through the JSON API, a playlist is created and read back through
# the API, the Subsonic API answers through front.php, and the cron service
# is running.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28415
recipe_init ampache
export AMPACHE_ADMIN_PASSWORD="recipe-pass-123"
export AMPACHE_HTTP_HOST="127.0.0.1"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/login.php" 200 300
    expect_status "$BASE/info.php" 404              # no ePHPm test fixtures (docroot is /app/public)
    expect_status "$BASE/phpinfo.php" 403

    # 1. log in through the login form
    local jar
    jar="$(cookie_jar)"
    curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/login.php"
    curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/login.php" \
        -F action=login -F username=admin -F "password=$AMPACHE_ADMIN_PASSWORD" -F referrer=
    expect_body "$BASE/index.php" 'logout.php' -b "$jar" -c "$jar"

    # 2. a catalog with one (generated) song, scanned by the CLI
    run_in ephpm mkdir -p "/media/music/Recipe Artist/Recipe Album"
    run_in ephpm ephpm php -r '
        $rate = 8000; $data = "";
        for ($i = 0; $i < $rate; $i++) { $data .= pack("v", (int) (8000 * sin(2 * M_PI * 440 * $i / $rate))); }
        file_put_contents($argv[1], "RIFF" . pack("V", 36 + strlen($data)) . "WAVEfmt " . pack("VvvVVvv", 16, 1, 1, $rate, $rate * 2, 2, 16) . "data" . pack("V", strlen($data)) . $data);
    ' -- "/media/music/Recipe Artist/Recipe Album/01 - Hello from ePHPm.wav"
    run_in ephpm ls -la "/media/music/Recipe Artist/Recipe Album/01 - Hello from ePHPm.wav" >/dev/null
    run_in ephpm php bin/cli run:addCatalog recipes /media/music music >/dev/null
    run_in ephpm php bin/cli run:updateCatalog -a recipes >/dev/null
    echo "==> catalog created and scanned"

    # 3. JSON API: handshake, find the song, stream it, playlist round trip
    local ts auth out token song_id
    ts="$(date +%s)"
    auth="$(printf '%s%s' "$ts" "$(printf '%s' "$AMPACHE_ADMIN_PASSWORD" | sha256sum | cut -d' ' -f1)" | sha256sum | cut -d' ' -f1)"
    out="$(curl -s "$BASE/server/json.server.php?action=handshake&auth=$auth&timestamp=$ts&user=admin&version=6.6.0")"
    token="$(printf '%s' "$out" | sed -nE 's/.*"auth": ?"([0-9a-f]+)".*/\1/p')"
    [ -n "$token" ] || { echo "!!! API handshake: $out" >&2; return 1; }
    echo "==> API handshake ok"
    out="$(curl -s "$BASE/server/json.server.php?action=songs&auth=$token&filter=Hello")"
    song_id="$(printf '%s' "$out" | tr -d ' \n' | sed -nE 's/.*"song":\[\{"id":"([0-9]+)".*/\1/p')"
    [ -n "$song_id" ] || { echo "!!! song not found through the API: $(printf '%s' "$out" | head -c 400)" >&2; return 1; }
    echo "==> song $song_id found"
    local code
    code="$(curl -s -o /dev/null -w '%{http_code} %{size_download}' "$BASE/server/json.server.php?action=stream&auth=$token&type=song&id=$song_id&format=raw" -L)"
    case "$code" in
        "200 "[1-9]*) echo "==> stream -> $code bytes" ;;
        *) echo "!!! stream -> $code" >&2; return 1 ;;
    esac
    expect_body "$BASE/server/json.server.php?action=playlist_create&auth=$token&name=Recipe+playlist&type=private" '"name": ?"Recipe playlist"'
    expect_body "$BASE/server/json.server.php?action=playlists&auth=$token&filter=Recipe" '"name": ?"Recipe playlist"'

    # 4. Subsonic API (/rest/<action>.view → rest/index.php via front.php)
    expect_body "$BASE/rest/ping.view?u=admin&p=$AMPACHE_ADMIN_PASSWORD&v=1.16.1&c=recipes&f=json" '"status": ?"ok"'

    # 5. the cron service is up (runs bin/cli run:cronProcess hourly)
    compose logs cron | grep -q 'running bin/cli run:cronProcess' || { echo "!!! cron service not running" >&2; return 1; }
    echo "==> cron service running"

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
