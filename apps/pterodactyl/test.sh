#!/usr/bin/env bash
# Smoke test: wait for migrations + seed + the admin user, log in the way the
# React login form does (JSON POST to /auth/login with the XSRF cookie), read
# the account through the client API, create a location through the admin
# area's form and read it back, and check that the queue worker and the
# scheduler sidecars run against the same database and Redis.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28604
recipe_init pterodactyl
export APP_URL="$BASE"
ADMIN="admin@example.com"
export PTERODACTYL_ADMIN_PASSWORD="Recipe-Pass-4417"

# xsrf — the XSRF-TOKEN cookie from the jar, URL-decoded (axios sends it as X-XSRF-TOKEN)
xsrf() {
    awk '$6 == "XSRF-TOKEN" { print $7 }' "$jar" | tail -1 \
        | sed 's/%3D/=/g; s/%2F/\//g; s/%2B/+/g'
}

compose_up
# the login page answers 200 once the panel has migrated and seeded
wait_http "$BASE/auth/login" 200 480
expect_body "$BASE/" "<title>Pterodactyl</title>"                # the React app shell

# 1. real workflow: log in through the same JSON endpoint the login form uses
jar="$(cookie_jar)"
expect_body "$BASE/auth/login" 'Pterodactyl' -c "$jar" -b "$jar"
expect_body "$BASE/auth/login" '"complete":true' -c "$jar" -b "$jar" \
    -H 'Accept: application/json' -H 'Content-Type: application/json' \
    -H 'X-Requested-With: XMLHttpRequest' -H "X-XSRF-TOKEN: $(xsrf)" \
    --data "{\"user\":\"$ADMIN\",\"password\":\"$PTERODACTYL_ADMIN_PASSWORD\"}"
expect_body "$BASE/api/client/account" "\"email\":\"$ADMIN\"" -c "$jar" -b "$jar" \
    -H 'Accept: application/json' -H 'X-Requested-With: XMLHttpRequest' -H "X-XSRF-TOKEN: $(xsrf)"

# 2. create a record: a location through the admin area's (Blade) form
token="$(form_value "$BASE/admin/locations" _token -c "$jar" -b "$jar")"
[ -n "$token" ] || { echo "!!! no _token on /admin/locations" >&2; exit 1; }
expect_status "$BASE/admin/locations" 302 -c "$jar" -b "$jar" \
    --data-urlencode "_token=$token" --data-urlencode "short=ephpm-test" \
    --data-urlencode "long=Created by the ePHPm recipe smoke test"
expect_body "$BASE/admin/locations" 'Created by the ePHPm recipe smoke test' -c "$jar" -b "$jar"

# 3. the sidecars: artisan on the embedded PHP against the same database and Redis
out="$(run_in queue ephpm php artisan queue:monitor redis:high,redis:standard,redis:low 2>&1)" \
    || { echo "!!! queue:monitor failed in the queue service: $out" >&2; exit 1; }
echo "==> queue service: artisan queue:monitor reached Redis"
# the worker has processed a real job: the welcome notification queued when
# the admin user was created
i=0
until compose logs queue 2>/dev/null | grep -E 'AccountCreated.*DONE' >/dev/null; do
    i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! the queue worker did not process AccountCreated" >&2; compose logs --tail=40 queue >&2; exit 1; }
    sleep 1
done
echo "==> queue service processed the AccountCreated notification job"
# scheduled commands are started with the `php` shim, not `ephpm` (Dockerfile)
bin="$(run_in scheduler ephpm php -r 'require "vendor/autoload.php"; echo Illuminate\Console\Application::phpBinary();' 2>/dev/null)"
case "$bin" in
    *"/usr/local/bin/php"*) echo "==> scheduler builds commands with $bin" ;;
    *) echo "!!! scheduled commands would run with '$bin'" >&2; exit 1 ;;
esac
out="$(run_in scheduler ephpm php artisan schedule:run 2>&1)" \
    || { echo "!!! schedule:run failed in the scheduler service: $out" >&2; exit 1; }
echo "$out" | tail -3
out="$(run_in ephpm ephpm php artisan p:location:make --short=cli-test --long=fromcli --no-interaction 2>&1 || true)"
expect_body "$BASE/admin/locations" 'cli-test' -c "$jar" -b "$jar"
rm -f "$jar"
