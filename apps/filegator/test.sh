#!/usr/bin/env bash
# Smoke test: the frontend loads, log in through the JSON API (session cookie
# + X-CSRF-Token, as the Vue app does), create a folder, upload a file
# (resumable.js chunk protocol), list the folder, download the file back,
# zip it; a bad CSRF token is refused; nothing above dist/ is served.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28612
recipe_init filegator
export FILEGATOR_ADMIN_PASSWORD="recipe-pass-123"

compose_up
wait_http "$BASE/" 200 120
# the base image's E2E fixtures (issues/joomla.md) must not be served
fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
expect_body "$BASE/" 'FileGator'
expect_body "$BASE/?r=/getconfig" '"app_version":"7\.16\.5"'

jar="$(cookie_jar)"
hdrs="$(native_path "$(mktemp)")"
# the CSRF token comes back as a response header on every request
token() { curl -s -o /dev/null -D "$hdrs" -c "$jar" -b "$jar" "$BASE/?r=/getuser"; tr -d '\r' < "$hdrs" | sed -n 's/^[Xx]-[Cc][Ss][Rr][Ff]-[Tt]oken: //p' | tail -1; }
api() {  # api ROUTE JSON
    curl -s -c "$jar" -b "$jar" -H "X-CSRF-Token: $(token)" -H 'Content-Type: application/json' \
        --data "$2" "$BASE/?r=$1"
}

# 1. a wrong CSRF token is refused (FileGator logs it and exits with an empty body)
body="$(curl -s -c "$jar" -b "$jar" -H 'X-CSRF-Token: nope' -H 'Content-Type: application/json' \
    --data "{\"username\":\"admin\",\"password\":\"$FILEGATOR_ADMIN_PASSWORD\"}" "$BASE/?r=/login")"
[ -z "$body" ] || { echo "!!! login with a bad CSRF token answered: $body" >&2; exit 1; }
echo "==> bad CSRF token refused"

# 2. log in (the password set from FILEGATOR_ADMIN_PASSWORD on first start)
api /login '{"username":"admin","password":"wrong"}' | grep '"data":"Login failed' >/dev/null \
    || { echo "!!! a wrong password was not refused" >&2; exit 1; }
api /login "{\"username\":\"admin\",\"password\":\"$FILEGATOR_ADMIN_PASSWORD\"}" | grep '"role":"admin"' >/dev/null \
    || { echo "!!! login failed" >&2; exit 1; }
echo "==> logged in as admin"

# 3. create a folder, change into it, upload a file into it (resumableRelativePath
#    is the destination directory, as the frontend sends it)
api /createnew '{"type":"dir","name":"reports"}' | grep '"data":"Done"' >/dev/null || { echo "!!! createnew failed" >&2; exit 1; }
api /changedir '{"to":"/reports"}' | grep -F '"location":"\/reports"' >/dev/null || { echo "!!! changedir failed" >&2; exit 1; }
payload="$(native_path "$(mktemp)")"
printf 'quarterly numbers from ephpm\n' > "$payload"
size="$(wc -c < "$payload" | tr -d ' ')"
up="$(curl -s -c "$jar" -b "$jar" -H "X-CSRF-Token: $(token)" \
    -F resumableChunkNumber=1 -F resumableChunkSize=1048576 -F resumableCurrentChunkSize="$size" \
    -F resumableTotalSize="$size" -F resumableType=text/plain -F resumableIdentifier="${size}-q1txt" \
    -F resumableFilename=q1.txt -F resumableRelativePath=/reports -F resumableTotalChunks=1 \
    -F "file=@${payload};filename=q1.txt" "$BASE/?r=/upload")"
rm -f "$payload"
printf '%s' "$up" | grep '"data":"Stored"' >/dev/null || { echo "!!! upload failed: $up" >&2; exit 1; }
echo "==> uploaded q1.txt"
api /getdir '{"dir":"/reports"}' | grep '"name":"q1.txt"' >/dev/null || { echo "!!! q1.txt not listed" >&2; exit 1; }
echo "==> /reports lists q1.txt"
run_in ephpm test -f /var/www/filegator/repository/reports/q1.txt
echo "==> stored in the repository volume"

# 4. download it back (path is base64), rename it, edit it in place
path64="$(printf '/reports/q1.txt' | base64)"
expect_body "$BASE/?r=/download&path=$path64" '^quarterly numbers from ephpm$' -b "$jar"
api /renameitem '{"from":"q1.txt","to":"q1-final.txt","destination":"/reports"}' | grep '"data":"Done"' >/dev/null \
    || { echo "!!! renameitem failed" >&2; exit 1; }
api /savecontent '{"name":"q1-final.txt","content":"edited on ePHPm\n"}' | grep '"data":"Done"' >/dev/null \
    || { echo "!!! savecontent failed" >&2; exit 1; }
expect_body "$BASE/?r=/download&path=$(printf '/reports/q1-final.txt' | base64)" '^edited on ePHPm$' -b "$jar"

# 5. Zip: ePHPm v0.11.3's ZipArchive cannot deflate (issues/filegator.md), so
#    the action fails there; report which way it went, check a real archive
#    when it works.
zipres="$(api /zipitems '{"name":"bundle.zip","items":[{"type":"file","path":"/reports/q1-final.txt","name":"q1-final.txt"}],"destination":"/reports"}' || true)"
if printf '%s' "$zipres" | grep '"data":"Done"' >/dev/null; then
    run_in ephpm sh -c 'head -c 2 /var/www/filegator/repository/reports/bundle.zip' | grep PK >/dev/null \
        || { echo "!!! bundle.zip is not a zip" >&2; exit 1; }
    echo "==> zipped into /reports/bundle.zip (the ZipArchive issue is fixed in this image)"
else
    echo "==> Zip action fails as expected on this image (issues/filegator.md): $zipres"
fi

# 6. logged out: the API refuses the listing
api /logout '{}' >/dev/null
code="$(curl -s -o /dev/null -w '%{http_code}' -c "$jar" -b "$jar" -H "X-CSRF-Token: $(token)" \
    -H 'Content-Type: application/json' --data '{"dir":"/"}' "$BASE/?r=/getdir")"
[ "$code" = 404 ] || [ "$code" = 401 ] || [ "$code" = 403 ] || { echo "!!! getdir after logout -> $code" >&2; exit 1; }
echo "==> getdir after logout -> $code"
rm -f "$jar" "$hdrs"

# 7. nothing outside dist/ is reachable
expect_status "$BASE/configuration.php" 404
expect_status "$BASE/../private/users.json" 404
