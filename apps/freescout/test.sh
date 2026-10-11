#!/usr/bin/env bash
# Smoke test: migrations + the admin user on first start; log in through the
# login form, create a mailbox through its form and read it back, check that
# the scheduler sidecar runs scheduled commands with the embedded PHP (not
# `ephpm artisan ...`, see the Dockerfile) and the queue worker is up.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28609
recipe_init freescout
export APP_URL="$BASE"
export FREESCOUT_ADMIN_PASSWORD="Recipe-Pass-8823"

compose_up
wait_http "$BASE/login" 200 300
expect_status "$BASE/" 302                                   # → /login

# 1. real workflow: log in
jar="$(cookie_jar)"
token="$(form_value "$BASE/login" _token -c "$jar" -b "$jar")"
[ -n "$token" ] || { echo "!!! no _token on /login" >&2; exit 1; }
expect_status "$BASE/login" 302 -c "$jar" -b "$jar" --data-urlencode "_token=$token" \
    --data "email=admin%40example.com" --data-urlencode "password=$FREESCOUT_ADMIN_PASSWORD"
expect_body "$BASE/mailboxes" 'logout-form' -c "$jar" -b "$jar"

# 2. create a record: a mailbox, read it back
page="$(curl -s -c "$jar" -b "$jar" "$BASE/mailbox/new")"
token="$(printf '%s' "$page" | grep -oE 'name="_token" value="[^"]+"' | sed -n '$s/.*value="\([^"]*\)"/\1/p')"
loc="$(curl -s -o /dev/null -w '%{redirect_url}' -c "$jar" -b "$jar" "$BASE/mailbox/new" \
    --data-urlencode "_token=$token" --data "name=ePHPm+Support&email=support%40example.com")"
case "$loc" in
    *"/mailbox/settings/"*) echo "==> mailbox created -> $loc" ;;
    *) echo "!!! creating a mailbox redirected to '$loc'" >&2; compose logs --tail=40 ephpm >&2; exit 1 ;;
esac
expect_body "$BASE/mailboxes" 'ePHPm Support' -c "$jar" -b "$jar"
expect_body "$loc" 'support@example.com' -c "$jar" -b "$jar"

# 3. nothing outside public/, and the .env is not served
expect_status "$BASE/.env" 403
expect_status "$BASE/vendor/autoload.php" 404
expect_status "$BASE/info.php" 404

# 4. the scheduler runs scheduled commands through the `php` shim …
i=0
until compose logs scheduler 2>/dev/null | grep -E "Running scheduled command: '/usr/local/bin/php' 'artisan'" >/dev/null; do
    i=$((i + 1)); [ "$i" -ge 120 ] && { echo "!!! the scheduler did not run a command through /usr/local/bin/php" >&2; compose logs --tail=40 scheduler >&2; exit 1; }
    sleep 1
done
echo "==> scheduler runs scheduled commands with /usr/local/bin/php"
if compose logs scheduler 2>/dev/null | grep -E "Running scheduled command: '/usr/local/bin/ephpm'" >/dev/null; then
    echo "!!! the scheduler still runs commands as 'ephpm artisan ...'" >&2; exit 1
fi
#    … and that command line works (the same one the scheduler builds)
run_in scheduler /usr/local/bin/php artisan freescout:fetch-monitor >/dev/null \
    || { echo "!!! '/usr/local/bin/php artisan freescout:fetch-monitor' failed in the scheduler service" >&2; exit 1; }
echo "==> '/usr/local/bin/php artisan freescout:fetch-monitor' runs in the scheduler service"
#    … and the queue worker is up on the queues FreeScout dispatches to
compose logs queue 2>/dev/null | grep -E '==> queue worker: emails,default,[0-9a-f]{32}' >/dev/null \
    || { echo "!!! queue worker did not start" >&2; compose logs --tail=40 queue >&2; exit 1; }
[ "$(compose ps --status running --services 2>/dev/null | grep -c '^queue$')" = 1 ] \
    || { echo "!!! the queue service is not running" >&2; compose logs --tail=40 queue >&2; exit 1; }
echo "==> queue worker running"
rm -f "$jar"
