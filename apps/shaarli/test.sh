#!/usr/bin/env bash
# Smoke test: complete Shaarli's web installer, log in, bookmark a link
# through the admin form, read it back on the public page, and check the
# session landed in ePHPm's KV store. Single compose variant (flat-file app).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28302
recipe_init shaarli

# Shaarli puts a session-bound CSRF token in every form.
form_token() { sed -n 's/.*name="token" value="\([^"]*\)".*/\1/p' | head -1; }

compose_up
# Not installed yet: the front page redirects to the installer.
wait_http "$BASE/" 302 120

jar="$(cookie_jar)"

# 1. installer — /install first bounces through /install/session-test to
#    prove sessions work (ours are in the KV store), then shows the form.
expect_body "$BASE/install" 'name="installform"' -L -c "$jar" -b "$jar"
expect_status "$BASE/install" 302 -c "$jar" -b "$jar" \
    --data-urlencode "setlogin=admin" --data-urlencode "setpassword=recipe-pass-123" \
    --data-urlencode "title=ePHPm Recipe" --data "language=auto&continent=Europe&city=Paris&enableApi=on&Save=Install"
expect_body "$BASE/" "ePHPm Recipe"

# 2. real workflow: log in
token="$(curl -s -c "$jar" -b "$jar" "$BASE/login" | form_token)"
[ -n "$token" ] || { echo "!!! no CSRF token on the login page" >&2; exit 1; }
expect_status "$BASE/login" 302 -c "$jar" -b "$jar" \
    --data-urlencode "login=admin" --data-urlencode "password=recipe-pass-123" \
    --data-urlencode "token=$token" --data "returnurl="
expect_body "$BASE/" 'admin/logout' -b "$jar"          # logged-in header

# 3. create a record: bookmark a link through the "Shaare" form
token="$(curl -s -c "$jar" -b "$jar" "$BASE/admin/shaare?post=https%3A%2F%2Fephpm.dev%2F" | form_token)"
[ -n "$token" ] || { echo "!!! no CSRF token on the shaare form" >&2; exit 1; }
expect_status "$BASE/admin/shaare" 302 -c "$jar" -b "$jar" \
    --data-urlencode "lf_url=https://ephpm.dev/" --data-urlencode "lf_title=Hello from ePHPm" \
    --data-urlencode "lf_description=Bookmarked through the recipe smoke test" \
    --data-urlencode "lf_tags=ephpm recipe" --data-urlencode "token=$token" \
    --data "source=&returnurl=&lf_id="
expect_body "$BASE/" "Hello from ePHPm"                 # public page, no cookie
expect_body "$BASE/feed/atom" "Hello from ePHPm"        # and the Atom feed

# 4. the session is in ePHPm's KV store (session.save_handler = ephpm)
run_in ephpm ephpm kv keys 'session:*' | grep 'session:' >/dev/null \
    || { echo "!!! no PHP session in the KV store" >&2; exit 1; }
echo "==> PHP session stored in the KV store"

# 5. private files are not served, and only index.php executes
expect_status "$BASE/data/config.json.php" 403
expect_status "$BASE/init.php" 403
rm -f "$jar"
