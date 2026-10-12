#!/usr/bin/env bash
# Smoke test: Piwigo installs unattended on the first start, the gallery
# answers 200, the admin logs in through the web API, creates an album,
# uploads a JPEG (resized by ImageMagick — ePHPm's GD has no JPEG), and the
# album, the photo and a generated thumbnail are read back. MariaDB only.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28410
recipe_init piwigo
export PIWIGO_ADMIN_PASSWORD="recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 240
    expect_body "$BASE/" "<title>Piwigo"       # the empty gallery's welcome page

    local jar api out cat_id img
    jar="$(cookie_jar)"
    api="$BASE/ws.php?format=json"

    # 1. log in as the installer-created admin (session cookie)
    expect_body "$api" '"stat":"ok","result":true' -c "$jar" -b "$jar" \
        --data "method=pwg.session.login&username=admin" --data-urlencode "password=$PIWIGO_ADMIN_PASSWORD"
    expect_body "$api" '"status":"webmaster"' -b "$jar" --data "method=pwg.session.getStatus"

    # 2. create an album
    out="$(curl -s -b "$jar" "$api" --data "method=pwg.categories.add" --data-urlencode "name=Hello from ePHPm")"
    cat_id="$(printf '%s' "$out" | sed -nE 's/.*"id":"?([0-9]+)"?.*/\1/p')"
    [ -n "$cat_id" ] || { echo "!!! pwg.categories.add: $out" >&2; return 1; }
    echo "==> album $cat_id created"

    # 3. upload a JPEG into it (made with the image's own ImageMagick)
    img="$(native_path "$(mktemp)").jpg"
    run_in ephpm convert -size 640x480 gradient:navy-orange /tmp/recipe.jpg
    compose cp ephpm:/tmp/recipe.jpg "$(compose_path "$img")"
    expect_body "$api" '"image_id":' -b "$jar" \
        -F method=pwg.images.addSimple -F "category=$cat_id" -F "name=Recipe photo" -F "image=@$img;type=image/jpeg"
    # new uploads wait in Piwigo's "lounge" until the client reports the
    # upload as finished (what the web uploader does)
    local token
    token="$(curl -s -b "$jar" "$api" --data "method=pwg.session.getStatus" | sed -nE 's/.*"pwg_token":"([0-9a-f]+)".*/\1/p')"
    [ -n "$token" ] || { echo "!!! no pwg_token" >&2; return 1; }
    expect_body "$api" '"stat":"ok"' -b "$jar" \
        --data "method=pwg.images.uploadCompleted&pwg_token=$token&category_id=$cat_id"

    # 4. read it back: the album lists the photo, the public album page
    #    shows it, and a square thumbnail is generated (i.php → ImageMagick)
    out="$(curl -s -b "$jar" "$api" --data "method=pwg.categories.getImages&cat_id=$cat_id")"
    printf '%s' "$out" | grep -q '"name":"Recipe photo"' || { echo "!!! photo not in album: $out" >&2; return 1; }
    echo "==> album $cat_id lists the uploaded photo"
    expect_body "$BASE/index.php?/category/$cat_id" "Hello from ePHPm" -b "$jar"
    local thumb
    thumb="$(printf '%s' "$out" | sed -nE 's/.*"square":\{"url":"([^"]+)".*/\1/p' | sed 's|[\]/|/|g')"
    [ -n "$thumb" ] || { echo "!!! no square derivative URL: $out" >&2; return 1; }
    local ct
    ct="$(curl -s -o /dev/null -w '%{http_code} %{content_type}' -b "$jar" "$thumb")"
    case "$ct" in
        "200 image/jpeg"*) echo "==> thumbnail $thumb -> $ct" ;;
        *) echo "!!! thumbnail $thumb -> $ct" >&2; compose logs --tail=80 >&2 || true; return 1 ;;
    esac

    # 5. credentials and logs are not served
    expect_status "$BASE/local/config/database.inc.php" 403
    expect_status "$BASE/install/piwigo_structure-mysql.sql" 403
    expect_status "$BASE/info.php" 404             # no ePHPm test fixtures, no catch-all

    rm -f "$jar" "$img"
    compose down -v --remove-orphans
}

run_variant compose.yml
