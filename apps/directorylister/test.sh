#!/usr/bin/env bash
# Smoke test: the listing renders, a file put into the data volume shows up,
# downloads through Directory Lister's ?file= handler, a sub-directory
# listing and its README render, search finds the file, a directory zip
# downloads, file info returns hashes; the code paths are not served.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28611
recipe_init directorylister

compose_up
wait_http "$BASE/" 200 120
# the base image's E2E fixtures (issues/joomla.md) must not be served
fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
expect_body "$BASE/" "Directory Lister"

# 1. put files into the listed volume
run_in ephpm sh -c 'mkdir -p /data/docs && echo "hello from ephpm" > /data/hello.txt \
    && printf "# Docs folder\n\nRendered **markdown**.\n" > /data/docs/README.md \
    && echo "nested" > /data/docs/nested.txt'

# 2. the listing shows them, downloads go through ?file=
expect_body "$BASE/" 'hello\.txt'
expect_body "$BASE/" '\?dir=docs'
expect_body "$BASE/?file=hello.txt" '^hello from ephpm$'
expect_body "$BASE/?dir=docs" 'nested\.txt'
expect_body "$BASE/?dir=docs" '<strong>markdown</strong>'      # README rendered
expect_body "$BASE/?search=nested" 'nested\.txt'
expect_body "$BASE/?info=hello.txt" '"sha1"'
zip="$(native_path "$(mktemp)")"
curl -s -o "$zip" "$BASE/?zip=docs"
[ "$(head -c 2 "$zip")" = "PK" ] || { echo "!!! ?zip=docs is not a zip" >&2; rm -f "$zip"; exit 1; }
rm -f "$zip"
echo "==> ?zip=docs is a zip archive"

# 3. traversal out of the data directory is refused
code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/?file=../etc/passwd")"
[ "$code" != 200 ] || { echo "!!! ?file=../etc/passwd answered 200" >&2; exit 1; }
echo "==> ?file=../etc/passwd -> $code"

# 4. static assets served; code and caches are not
asset="$(curl -s "$BASE/" | grep -oE 'app/assets/app-[A-Za-z0-9_-]+\.css' | head -1)"
expect_status "$BASE/$asset" 200
expect_status "$BASE/app/config/app.php" 403
expect_status "$BASE/app/vendor/autoload.php" 403
expect_status "$BASE/app/src/HiddenFiles.php" 403
