#!/usr/bin/env bash
# Smoke test: the container installs GLPI with bin/console on first start;
# then log in as glpi/glpi through the login form, create a computer through
# the asset form (a legacy /front/*.php script routed by public/index.php)
# and read it back in the list, check that code/config outside public/ is
# not reachable, and that the cron sidecar runs front/cron.php.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28605
recipe_init glpi

compose_up
wait_http "$BASE/" 200 480                                  # after the CLI install
expect_body "$BASE/" 'name="login_password"'

# 1. real workflow: log in with the default super-admin account
jar="$(cookie_jar)"
curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/"
expect_status "$BASE/front/login.php" 302 -c "$jar" -b "$jar" \
    --data "noAUTO=0&redirect=&login_name=glpi&login_password=glpi&login_remember=on"
expect_body "$BASE/front/central.php" '<title>Standard interface - GLPI' -c "$jar" -b "$jar"

# 2. create a record: a computer through the asset form, read it back
loc="$(curl -s -o /dev/null -w '%{redirect_url}' -c "$jar" -b "$jar" "$BASE/front/computer.form.php" \
    -H "Origin: $BASE" -e "$BASE/front/computer.form.php" \
    --data "entities_id=0&name=ephpm-recipe-pc&serial=EPHPM-SERIAL-42&add=1")"
case "$loc" in
    *"/front/computer.form.php?id="*) echo "==> computer created -> $loc" ;;
    *) echo "!!! creating a computer redirected to '$loc'" >&2; compose logs --tail=60 ephpm >&2; exit 1 ;;
esac
expect_body "$BASE/front/computer.php" 'ephpm-recipe-pc' -c "$jar" -b "$jar"
# (the form's fields are loaded as a tab through ajax/common.tabs.php)
id="${loc##*id=}"
expect_body "$BASE/ajax/common.tabs.php?_glpi_tab=Computer%24main&_target=%2Ffront%2Fcomputer.form.php&_itemtype=Computer&id=$id" \
    'EPHPM-SERIAL-42' -c "$jar" -b "$jar" -H 'X-Requested-With: XMLHttpRequest'

# 3. nothing outside public/ is served (the router answers 404)
expect_status "$BASE/config/config_db.php" 404
expect_status "$BASE/vendor/autoload.php" 404
expect_status "$BASE/files/_log/php-errors.log" 404

# 4. the CLI and the cron sidecar run on the embedded PHP
run_in ephpm ephpm php bin/console db:check >/dev/null || { echo "!!! bin/console db:check failed" >&2; exit 1; }
echo "==> bin/console db:check passed"
i=0
until compose logs cron 2>/dev/null | grep -E 'front/cron.php every 60' >/dev/null; do
    i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! cron sidecar did not start" >&2; compose logs --tail=40 cron >&2; exit 1; }
    sleep 1
done
run_in cron ephpm php front/cron.php || { echo "!!! front/cron.php failed in the cron service" >&2; exit 1; }
if compose logs cron 2>&1 | grep -E "exited with" >/dev/null; then
    echo "!!! the cron loop reported a failed run:" >&2; compose logs --tail=40 cron >&2; exit 1
fi
echo "==> cron service ran front/cron.php"
rm -f "$jar"
