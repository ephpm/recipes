#!/usr/bin/env bash
# Smoke test: Tiny File Manager answers, the admin logs in through the login
# form (CSRF token), creates a folder, uploads a file into it the way the
# Dropzone uploader does, downloads it back, and the managed files and the
# generated config.php are not reachable directly.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28411
recipe_init tinyfilemanager
export TFM_ADMIN_PASSWORD="recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 120
    expect_body "$BASE/" 'name="fm_usr"'

    local jar token file
    jar="$(cookie_jar)"
    # 1. log in (form + CSRF token bound to the session)
    token="$(form_value "$BASE/" token -c "$jar" -b "$jar")"
    [ -n "$token" ] || { echo "!!! no login token" >&2; return 1; }
    curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/" \
        --data-urlencode "fm_usr=admin" --data-urlencode "fm_pwd=$TFM_ADMIN_PASSWORD" --data-urlencode "token=$token"
    expect_body "$BASE/?p=" 'logout' -b "$jar"
    token="$(curl -s -b "$jar" "$BASE/?p=" | sed -nE 's/.*name="token" value="([0-9a-f]+)".*/\1/p' | head -1)"
    [ -n "$token" ] || { echo "!!! no session token after login" >&2; return 1; }

    # 2. create a folder
    curl -s -o /dev/null -b "$jar" "$BASE/?p=" --data "newfile=folder&newfilename=docs&token=$token"
    expect_body "$BASE/?p=" 'p=docs' -b "$jar"

    # 3. upload a file into it (Dropzone's single-chunk POST)
    file="$(native_path "$(mktemp)")"
    printf 'Hello from ePHPm\n' > "$file"
    expect_body "$BASE/?p=docs" '"status":"success"' -b "$jar" \
        -F "token=$token" -F "dzchunkindex=0" -F "dztotalchunkcount=1" -F "fullpath=hello.txt" \
        -F "file=@$file;filename=hello.txt;type=text/plain"

    # 4. read it back: listed in the folder, and downloaded with its content
    expect_body "$BASE/?p=docs" 'hello.txt' -b "$jar"
    expect_body "$BASE/?p=docs&dl=hello.txt" '^Hello from ePHPm$' -b "$jar" --data "token=$token"
    out="$(run_in ephpm cat /data/docs/hello.txt)"
    [ "$out" = "Hello from ePHPm" ] || { echo "!!! /data/docs/hello.txt: $out" >&2; return 1; }
    echo "==> /data/docs/hello.txt is on the volume"

    # 5. nothing but the app is served
    expect_status "$BASE/config.php" 403
    expect_status "$BASE/docs/hello.txt" 404
    expect_status "$BASE/info.php" 404

    rm -f "$jar" "$file"
    compose down -v --remove-orphans
}

run_variant compose.yml
