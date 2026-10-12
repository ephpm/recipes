#!/usr/bin/env bash
# Smoke test: wait for migrations, log in as the seeded administrator.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28160
recipe_init projectsend
export APP_URL="$BASE"
compose_up
wait_http "$BASE/login" 200 300

# Inertia SPA: the login form posts JSON with the XSRF cookie echoed back
# in X-XSRF-TOKEN (the cookie is named laravel_xsrf here, URL-encoded).
jar="$(cookie_jar)"
curl -s -o /dev/null --max-time 30 -c "$jar" -b "$jar" "$BASE/login"
xsrf="$(awk '$6=="laravel_xsrf"{print $7}' "$jar" | sed 's/%3D/=/g;s/%2B/+/g;s/%2F/\//g')"
loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 60 -c "$jar" -b "$jar" \
    -H "X-XSRF-TOKEN: $xsrf" -H 'X-Inertia: true' -H 'Accept: application/json' -H 'Content-Type: application/json' \
    -d '{"email":"admin@example.com","password":"ProjectSend-Admin-Pass-1"}' "$BASE/login")"
case "$loc" in
    *dashboard*) echo "==> login -> $loc" ;;
    *) echo "!!! login redirected to '$loc'" >&2; compose logs --tail=50 >&2; exit 1 ;;
esac
expect_body "$BASE/dashboard" "admin@example.com" -L -b "$jar" -c "$jar"
out="$(run_in ephpm ephpm php artisan migrate:status --no-ansi)"
case "$out" in *Ran*) echo "==> artisan migrate:status ok" ;; *) echo "!!! $out" >&2; exit 1 ;; esac
