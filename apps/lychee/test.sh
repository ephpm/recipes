#!/usr/bin/env bash
# Smoke test: Lychee migrates and creates the admin on the first start, the
# gallery answers, the admin logs in through the JSON API (XSRF token),
# creates an album and finds it in the album list, uploads a PNG into it,
# and the photo is listed in the album.
#
# On ePHPm v0.11.3 the upload step FAILS: Lychee generates WebP size
# variants and ePHPm's GD has no WebP (issues/koel.md) — see the README.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28414
recipe_init lychee
export APP_URL="$BASE"
export LYCHEE_ADMIN_PASSWORD="recipe-pass-123"

jar=""
xsrf() { awk '$6=="XSRF-TOKEN"{print $7}' "$jar" | sed 's/%3D/=/g'; }
api() { # api METHOD PATH [curl args...] — JSON API call with the session + XSRF header
    local m="$1" p="$2"; shift 2
    curl -s -X "$m" -b "$jar" -c "$jar" -H "Accept: application/json" -H "X-XSRF-TOKEN: $(xsrf)" "$@" "$BASE/api/v2/$p"
}

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 240
    expect_status "$BASE/info.php" 404      # no ePHPm test fixtures (docroot is /app/public)

    jar="$(cookie_jar)"
    curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/"

    # 1. log in (JSON API, Laravel's XSRF cookie echoed as a header)
    local code out album png
    code="$(api POST 'Auth::login' -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
        --data "{\"username\":\"admin\",\"password\":\"$LYCHEE_ADMIN_PASSWORD\"}")"
    [ "$code" = 204 ] || { echo "!!! login -> $code" >&2; return 1; }
    out="$(api GET 'Auth::user' -H 'Content-Type: application/json')"
    printf '%s' "$out" | grep -q '"may_administrate":true' || { echo "!!! Auth::user: $out" >&2; return 1; }
    echo "==> logged in as admin"

    # 2. create an album and find it in the album list
    album="$(api POST 'Album' -H 'Content-Type: application/json' --data '{"title":"Hello from ePHPm","parent_id":null}' | tr -d '"')"
    [ -n "$album" ] || { echo "!!! album not created" >&2; return 1; }
    api GET 'Albums' -H 'Content-Type: application/json' | grep -q '"title":"Hello from ePHPm"' \
        || { echo "!!! album $album not listed" >&2; return 1; }
    echo "==> album $album created and listed"

    # 3. upload a PNG (made with the embedded PHP's GD) and read it back
    png="$(native_path "$(mktemp)").png"
    run_in ephpm ephpm php -r '$i = imagecreatetruecolor(320, 240); imagefill($i, 0, 0, imagecolorallocate($i, 30, 90, 200)); imagepng($i, "/tmp/recipe.png");'
    compose cp ephpm:/tmp/recipe.png "$(compose_path "$png")"
    out="$(api POST 'Photo' -F "album_id=$album" -F "file=@$png;filename=recipe.png;type=image/png" \
        -F file_name=recipe.png -F uuid_name= -F extension= -F chunk_number=1 -F total_chunks=1)"
    printf '%s' "$out" | grep -q '"stage":"done"' || { echo "!!! upload: $out" >&2; return 1; }
    out="$(api GET "Album::photos?album_id=$album" -H 'Content-Type: application/json')"
    printf '%s' "$out" | grep -q '"photos":\[{"id"' || { echo "!!! uploaded photo not in album $album: $out" >&2; return 1; }
    echo "==> photo listed in album $album"
    # … with its generated thumbnail (Lychee writes size variants as WebP)
    printf '%s' "$out" | grep -qE '"thumb":\{[^}]*"url":"[^"]+' || {
        echo "!!! the photo has no thumbnail size variant" >&2
        run_in ephpm sh -c 'tail -n 5 storage/logs/errors.log' >&2 || true
        return 1; }
    echo "==> thumbnail generated"

    rm -f "$jar" "$png"
    compose down -v --remove-orphans
}

run_variant compose.yml
