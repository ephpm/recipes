#!/usr/bin/env bash
# Smoke test: the container installs phpBB with its CLI installer, then we
# log in as the admin, post a new topic through posting.php, read it back on
# the forum, hit an app.php controller route (FAQ) and the Atom feed, and run
# the CLI on the embedded PHP. Single compose variant (MariaDB).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28601
recipe_init phpbb

export PHPBB_SERVER_NAME=127.0.0.1 PHPBB_SERVER_PORT="$PORT" PHPBB_ADMIN_PASS="recipe-pass-123"

compose_up
wait_http "$BASE/" 200 300                         # after the CLI install
expect_body "$BASE/" 'ePHPm Board'

# load_form URL — GET a form page once (with the cookie jar) into $form;
# field NAME — print a hidden field's value from it. phpBB's form_token is
# bound to the creation_time and session of the same page view, so both
# must come from one fetch.
load_form() { form="$(curl -s --max-time 30 -c "$jar" -b "$jar" "$1")"; }
field() { printf '%s' "$form" | grep -oE "name=\"$1\" value=\"[^\"]*\"" | sed -n '1s/.*value="\([^"]*\)"/\1/p'; }

# 1. real workflow: log in through the login form
jar="$(cookie_jar)"
login="$BASE/ucp.php?mode=login"
load_form "$login"
[ -n "$(field form_token)" ] && [ -n "$(field creation_time)" ] || { echo "!!! no form_token/creation_time on the login form" >&2; exit 1; }
expect_status "$login" 302 -c "$jar" -b "$jar" \
    --data-urlencode "form_token=$(field form_token)" --data-urlencode "creation_time=$(field creation_time)" \
    --data-urlencode "sid=$(field sid)" \
    --data "username=admin&password=$PHPBB_ADMIN_PASS&login=Login&redirect=index.php"
expect_body "$BASE/index.php" 'mode=logout' -b "$jar" -c "$jar"   # logged in

# 2. create a record: a topic in the default forum (id 2, "Your first forum")
post="$BASE/posting.php?mode=post&f=2"
load_form "$post"
[ -n "$(field form_token)" ] || { echo "!!! no form_token on the posting form" >&2; exit 1; }
sleep 3                                                     # phpBB rejects forms submitted within 2 s of creation
expect_status "$post" 302 -c "$jar" -b "$jar" \
    --data-urlencode "form_token=$(field form_token)" --data-urlencode "creation_time=$(field creation_time)" \
    --data-urlencode "lastclick=$(field lastclick)" --data-urlencode "subject=Hello from ePHPm" \
    --data-urlencode "message=A topic posted by the recipe smoke test." --data "post=Submit"
expect_body "$BASE/viewforum.php?f=2" 'Hello from ePHPm' -b "$jar"

# 3. controller routes go through app.php via [server] fallback (no PATH_INFO needed)
expect_body "$BASE/app.php/help/faq" 'FAQ'
expect_body "$BASE/app.php/feed" 'Hello from ePHPm'         # the board's Atom feed

# 4. the CLI runs on the embedded PHP
run_in ephpm php bin/phpbbcli.php cache:purge >/dev/null || { echo "!!! phpbbcli.php cache:purge failed" >&2; exit 1; }
run_in ephpm php bin/phpbbcli.php config:get sitename | grep 'ePHPm Board' >/dev/null || { echo "!!! phpbbcli.php config:get failed" >&2; exit 1; }
echo "==> bin/phpbbcli.php ran on the embedded PHP"

# 5. private paths are not served, install/ is gone
expect_status "$BASE/config.php" 403
expect_status "$BASE/phpbb/db/driver/mysqli.php" 403
expect_status "$BASE/install/app.php" 403
# the base image's E2E fixtures (issues/joomla.md) were removed in the Dockerfile
[ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/info.php")" != 200 ] || { echo "!!! the base image's info.php fixture is served" >&2; exit 1; }
rm -f "$jar"
