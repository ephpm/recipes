#!/usr/bin/env bash
# Smoke test: load the page, create a paste through PrivateBin's JSON API
# (the browser encrypts client-side and POSTs the same structure), read it
# back, delete it with its delete token, and check the private paths are not
# served. Single compose variant (flat-file app).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28304
recipe_init privatebin

compose_up
wait_http "$BASE/" 200 120
expect_body "$BASE/" 'PrivateBin'

# 1. real workflow: create a paste. PrivateBin never sees plaintext — the
#    client sends cipher parameters + ciphertext (FormatV2); random bytes
#    stand in for the ciphertext here.
iv="$(head -c 16 /dev/urandom | base64 | tr -d '\n')"      # 16 bytes → 24 chars
salt="$(head -c 8 /dev/urandom | base64 | tr -d '\n')"     # 8 bytes → 12 chars
ct="$(head -c 512 /dev/urandom | base64 | tr -d '\n')"
paste="{\"v\":2,\"adata\":[[\"$iv\",\"$salt\",100000,256,128,\"aes\",\"gcm\",\"zlib\"],\"plaintext\",0,0],\"ct\":\"$ct\",\"meta\":{\"expire\":\"1week\"}}"
resp="$(curl -s -H 'X-Requested-With: JSONHttpRequest' -H 'Content-Type: application/json' --data "$paste" "$BASE/")"
printf '%s' "$resp" | grep '"status":0' >/dev/null || { echo "!!! paste creation failed: $resp" >&2; exit 1; }
id="$(printf '%s' "$resp" | sed -n 's/.*"id":"\([0-9a-f]*\)".*/\1/p')"
deletetoken="$(printf '%s' "$resp" | sed -n 's/.*"deletetoken":"\([0-9a-f]*\)".*/\1/p')"
[ -n "$id" ] && [ -n "$deletetoken" ] || { echo "!!! no id/deletetoken in: $resp" >&2; exit 1; }
echo "==> paste $id created"

# 2. read it back (as the browser does, before decrypting); json_encode escapes
#    "/" as "\/", so unescape before comparing the ciphertext
body="$(curl -s -H 'X-Requested-With: JSONHttpRequest' "$BASE/?$id" | sed 's#\\/#/#g')"
printf '%s' "$body" | grep '"status":0' >/dev/null || { echo "!!! reading paste $id failed: $body" >&2; exit 1; }
printf '%s' "$body" | grep -F "\"ct\":\"$ct\"" >/dev/null || { echo "!!! ciphertext did not round-trip" >&2; exit 1; }
echo "==> paste $id read back with its ciphertext intact"
# …and it is on disk in the data volume
run_in ephpm sh -c 'ls /srv/data | grep -v "^\\.\\|salt\\|traffic\\|purge" | head -1 | grep .' >/dev/null \
    || { echo "!!! no paste file under /srv/data" >&2; exit 1; }
echo "==> paste stored under /srv/data"

# 3. delete it with the delete token, then it is gone
expect_body "$BASE/?pasteid=$id&deletetoken=$deletetoken" '"status":0' -H 'X-Requested-With: JSONHttpRequest'
expect_body "$BASE/?$id" '"status":1' -H 'X-Requested-With: JSONHttpRequest'
echo "==> paste deleted"

# 4. code and config are outside the web root (/srv), so /cfg/… /lib/… /vendor/…
#    do not exist there — the fallback hands such URLs to index.php, which just
#    renders the paste page; nothing of the config can leak
run_in ephpm sh -c 'test ! -e /var/www/cfg && test ! -e /var/www/lib && test ! -e /var/www/vendor && test -f /srv/cfg/conf.php' \
    || { echo "!!! cfg/lib/vendor found inside the web root" >&2; exit 1; }
curl -s "$BASE/cfg/conf.php" | grep -E 'model_options|sizelimit' >/dev/null \
    && { echo "!!! /cfg/conf.php leaked configuration" >&2; exit 1; }
echo "==> cfg/, lib/, vendor/ live outside the web root; /cfg/conf.php leaks nothing"
