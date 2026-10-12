#!/usr/bin/env bash
# Smoke test: schema + superadmin created on start, log in through the form,
# create a domain through the admin UI and read it back, run the CLI.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28171
recipe_init postfixadmin
export POSTFIXADMIN_SETUP_PASSWORD="Setup-pass-12345" POSTFIXADMIN_ADMIN_PASSWORD="Admin-pass-12345"
compose_up
wait_http "$BASE/login.php" 200 240
jar="$(cookie_jar)"
tok="$(form_value "$BASE/login.php" token -c "$jar" -b "$jar")"
curl -s -o /dev/null --max-time 30 -c "$jar" -b "$jar" --data-urlencode "token=$tok" \
    --data-urlencode "fUsername=admin@example.org" --data-urlencode "fPassword=$POSTFIXADMIN_ADMIN_PASSWORD" --data "lang=en&submit=Login" "$BASE/login.php"
expect_body "$BASE/main.php" "Logout|logout" -c "$jar" -b "$jar"
tok="$(form_value "$BASE/edit.php?table=domain" token -c "$jar" -b "$jar")"
curl -s -o /dev/null --max-time 30 -c "$jar" -b "$jar" --data-urlencode "token=$tok" \
    --data "table=domain&value%5Bdomain%5D=recipe-test.example&value%5Bdescription%5D=smoke&value%5Baliases%5D=0&value%5Bmailboxes%5D=0&value%5Bmaxquota%5D=0&value%5Bquota%5D=0&value%5Bpassword_expiry%5D=0&value%5Bactive%5D=1&submit=Add+Domain" \
    "$BASE/edit.php?table=domain"
expect_body "$BASE/list.php?table=domain" "recipe-test.example" -c "$jar" -b "$jar"
out="$(run_in ephpm php scripts/postfixadmin-cli.php domain view recipe-test.example || true)"
case "$out" in *recipe-test.example*) echo "==> postfixadmin-cli sees the domain" ;; *) echo "!!! cli: $out" >&2; exit 1 ;; esac
rm -f "$jar"
