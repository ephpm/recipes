#!/usr/bin/env bash
# Smoke test: unattended install, log in as admin, upload a file through the
# upload form and download it back.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28174
recipe_init xbackbone
export XBACKBONE_ADMIN_PASSWORD="Recipe-pass-1234"
export XBACKBONE_BASE_URL="$BASE"
compose_up
wait_http "$BASE/login" 200 120
jar="$(cookie_jar)"
tok="$(form_value "$BASE/login" _token -c "$jar" -b "$jar")"
curl -s -o /dev/null --max-time 30 -c "$jar" -b "$jar" --data-urlencode "_token=$tok" \
    --data-urlencode "username=admin@example.org" --data-urlencode "password=$XBACKBONE_ADMIN_PASSWORD" "$BASE/login"
expect_body "$BASE/home" "logout|Logout" -c "$jar" -b "$jar"
# the upload API needs the user's token: generate one, then upload with it
utok="$(curl -s --max-time 30 -c "$jar" -b "$jar" -X POST "$BASE/user/1/refreshToken")"
case "$utok" in token_*) echo "==> upload token issued" ;; *) echo "!!! refreshToken: $utok" >&2; exit 1 ;; esac
f="$(native_path "$(mktemp)")"
printf 'hello from the recipe smoke test' > "$f"
up="$(curl -s --max-time 60 -F "token=$utok" -F "upload=@$f;type=text/plain" "$BASE/upload")"
echo "==> upload response: $(printf '%s' "$up" | head -c 200)"
url="$(printf '%s' "$up" | sed -nE 's/.*"raw_url":"([^"]+)".*/\1/p' | tr -d '\')"
[ -n "$url" ] || { echo "!!! no raw_url in upload response" >&2; exit 1; }
expect_body "$url" "hello from the recipe smoke test"
rm -f "$jar"
