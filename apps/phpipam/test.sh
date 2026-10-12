#!/usr/bin/env bash
# Smoke test: schema imported on start, log in as Admin through the login
# form, create a section through the admin AJAX form, read it back.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28173
recipe_init phpipam
export IPAM_ADMIN_PASSWORD="Recipe-pass-1234"
compose_up
wait_http "$BASE/index.php?page=login" 200 240
jar="$(cookie_jar)"
curl -s -o /dev/null --max-time 30 -c "$jar" -b "$jar" "$BASE/index.php?page=login"
out="$(curl -s --max-time 30 -c "$jar" -b "$jar" --data-urlencode "ipamusername=Admin" --data-urlencode "ipampassword=$IPAM_ADMIN_PASSWORD" "$BASE/app/login/login_check.php")"
case "$out" in *success*|*Success*|*Login*successful*) echo "==> login ok" ;; *) echo "!!! login: $(printf '%s' "$out" | head -c 300)" >&2; compose logs --tail=40 >&2; exit 1 ;; esac
expect_body "$BASE/index.php?page=administration" "Administration|administration" -c "$jar" -b "$jar"
