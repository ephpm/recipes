#!/usr/bin/env bash
# Smoke test: the first request runs the installer (autoconfig.php), log in
# through the web login form, upload a file over WebDAV (/remote.php/dav —
# dispatched by ephpm-pathinfo.php), list it with PROPFIND and read it back,
# read the user through the OCS API (/ocs/v2.php), check the code
# directories are refused, and run a background job through /cron.php from
# the cron service.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28403
recipe_init nextcloud
export NEXTCLOUD_ADMIN_USER=admin
export NEXTCLOUD_ADMIN_PASSWORD="Recipe-Nc-Pass-9731"
AUTH="$NEXTCLOUD_ADMIN_USER:$NEXTCLOUD_ADMIN_PASSWORD"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # status.php answers once ePHPm is up and the database reachable …
    wait_http "$BASE/status.php" 200 300
    # … and the first page request runs the installer (a minute or two)
    curl -s -o /dev/null --max-time 900 "$BASE/" || true
    local i=0
    until curl -s --max-time 10 "$BASE/status.php" | grep -q '"installed":true'; do
        i=$((i + 1)); [ "$i" -ge 300 ] && { echo "!!! not installed" >&2; compose logs --tail=80 >&2; return 1; }
        sleep 1
    done
    echo "==> installed: $(curl -s "$BASE/status.php")"
    wait_http "$BASE/login" 200 60

    # 1. log in through the login form (requesttoken from the page)
    local jar tok loc
    jar="$(cookie_jar)"
    tok="$(curl -s -c "$jar" -b "$jar" "$BASE/login" | sed -nE 's/.*data-requesttoken="([^"]+)".*/\1/p' | head -1)"
    [ -n "$tok" ] || { echo "!!! no requesttoken on /login" >&2; return 1; }
    # (Nextcloud refuses a login POST whose Origin is not a trusted domain)
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' -c "$jar" -b "$jar" -H "Origin: $BASE" \
        --data-urlencode "user=$NEXTCLOUD_ADMIN_USER" --data-urlencode "password=$NEXTCLOUD_ADMIN_PASSWORD" \
        --data-urlencode "requesttoken=$tok" "$BASE/login")"
    case "$loc" in
        */apps/*) echo "==> logged in, redirected to $loc" ;;
        *) echo "!!! login redirected to '$loc'" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac
    expect_body "$BASE/apps/files/" 'data-requesttoken' -c "$jar" -b "$jar"
    expect_body "$BASE/index.php/apps/files/" 'data-requesttoken' -c "$jar" -b "$jar"   # the /index.php/... form too

    # 2. WebDAV: upload a file, list the folder, read the file back
    expect_status "$BASE/remote.php/dav/files/admin/ephpm-recipe.txt" 201 -u "$AUTH" \
        -X PUT --data-binary "hello from ePHPm"
    expect_body "$BASE/remote.php/dav/files/admin/" 'ephpm-recipe\.txt' -u "$AUTH" \
        -X PROPFIND -H 'Depth: 1'
    expect_body "$BASE/remote.php/dav/files/admin/ephpm-recipe.txt" '^hello from ePHPm$' -u "$AUTH"

    # 3. OCS API (also a PATH_INFO entry point)
    expect_body "$BASE/ocs/v2.php/cloud/user?format=json" '"id":"admin"' -u "$AUTH" -H 'OCS-APIRequest: true'

    # 4. the code and data directories are not served
    expect_status "$BASE/config/config.php" 403
    expect_status "$BASE/data/nextcloud.log" 403
    expect_status "$BASE/lib/base.php" 403

    # 5. a background-job run through /cron.php, the way the cron service does it
    local out
    out="$(run_in cron ephpm php -r 'echo file_get_contents("http://ephpm:8080/cron.php", false, stream_context_create(["http" => ["header" => "Host: localhost\r\n"]]));')"
    case "$out" in
        *'"status":"success"'*) echo "==> cron.php: $out" ;;
        *) echo "!!! cron.php answered: $out" >&2; return 1 ;;
    esac

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
