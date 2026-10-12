#!/usr/bin/env bash
# Smoke test: complete DokuWiki's web installer, log in as the superuser,
# create a page through the editor, read it back, and check the session is in
# ePHPm's KV store. Single compose variant (flat-file app).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28308
recipe_init dokuwiki

compose_up
wait_http "$BASE/install.php" 200 120
# the base image's E2E fixtures (issues/joomla.md) must not be served
fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
expect_body "$BASE/install.php" 'name="d\[superuser\]"'

# 1. installer
expect_body "$BASE/install.php" 'finished successfully' \
    --data "l=en&submit=Save" \
    --data-urlencode "d[title]=ePHPm Recipe" --data "d[acl]=1&d[superuser]=admin" \
    --data-urlencode "d[fullname]=Recipe Admin" --data-urlencode "d[email]=admin@example.com" \
    --data "d[password]=recipe-pass-123&d[confirm]=recipe-pass-123&d[policy]=0&d[allowreg]=0&d[license]=cc-by-sa&d[pop]=0"
run_in ephpm test -f conf/local.php || { echo "!!! conf/local.php was not written by the installer" >&2; exit 1; }
expect_body "$BASE/doku.php" "ePHPm Recipe"

# 2. real workflow: log in (DokuWiki issues no security token to anonymous
#    users, so the login form posts an empty sectok)
jar="$(cookie_jar)"
curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/doku.php?do=login"
expect_status "$BASE/doku.php" 302 -c "$jar" -b "$jar" \
    --data "sectok=&do=login&id=start&u=admin&p=recipe-pass-123&r=1"
expect_body "$BASE/doku.php?id=start" 'do=logout' -b "$jar"      # logged in: the logout action is offered

# 3. create a page through the editor (hidden fields come from the edit form)
edit="$BASE/doku.php?id=ephpm&do=edit"
sectok="$(form_value "$edit" sectok -c "$jar" -b "$jar")"
changecheck="$(form_value "$edit" changecheck -c "$jar" -b "$jar" || true)"
expect_status "$BASE/doku.php" 302 -c "$jar" -b "$jar" \
    --data-urlencode "sectok=$sectok" --data-urlencode "changecheck=$changecheck" \
    --data "id=ephpm&rev=&date=0&prefix=.&suffix=&target=section&do%5Bsave%5D=Save&summary=created" \
    --data-urlencode "wikitext======= Hello from ePHPm ======
A page saved through the recipe smoke test."
expect_body "$BASE/doku.php?id=ephpm" "Hello from ePHPm"
run_in ephpm test -f data/pages/ephpm.txt || { echo "!!! data/pages/ephpm.txt missing" >&2; exit 1; }
echo "==> page stored in the data volume"

# 4. the session lives in ePHPm's KV store (session.save_handler = ephpm)
run_in ephpm ephpm kv keys 'session:*' | grep 'session:' >/dev/null \
    || { echo "!!! no PHP session in the KV store" >&2; exit 1; }
echo "==> PHP session stored in the KV store"

# 5. private directories are not served
expect_status "$BASE/conf/local.php" 403
expect_status "$BASE/data/pages/ephpm.txt" 403
expect_status "$BASE/inc/init.php" 403
rm -f "$jar"
