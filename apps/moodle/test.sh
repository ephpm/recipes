#!/usr/bin/env bash
# Smoke test: the container installs Moodle with admin/cli/install_database.php
# on first start; then log in through the login form, open the dashboard and
# its theme CSS/JS (query-string URLs: no slash arguments), create a course
# through the course form and read it back, and check the cron sidecar and
# the admin CLI on the embedded PHP.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28608
recipe_init moodle
# Moodle redirects any request whose host/port differs from wwwroot.
export MOODLE_WWWROOT="$BASE"
export MOODLE_ADMIN_PASSWORD="Recipe-Pass-5501!"

compose_up
wait_http "$BASE/login/index.php" 200 600                   # after the CLI install

# 1. real workflow: log in through the login form
jar="$(cookie_jar)"
token="$(form_value "$BASE/login/index.php" logintoken -c "$jar" -b "$jar")"
[ -n "$token" ] || { echo "!!! no logintoken on the login form" >&2; exit 1; }
expect_status "$BASE/login/index.php" 303 -c "$jar" -b "$jar" \
    --data "anchor=&logintoken=$token&username=admin" --data-urlencode "password=$MOODLE_ADMIN_PASSWORD"
dash="$(curl -s -L -c "$jar" -b "$jar" "$BASE/my/")"
case "$dash" in
    *"<title>Dashboard"*) echo "==> logged in: dashboard" ;;
    *) echo "!!! no dashboard after login" >&2; printf '%s' "$dash" | head -c 1500 >&2; exit 1 ;;
esac
sesskey="$(printf '%s' "$dash" | grep -oE '"sesskey":"[^"]*"' | sed -n '1s/.*:"\(.*\)"/\1/p')"
[ -n "$sesskey" ] || { echo "!!! no sesskey on the dashboard" >&2; exit 1; }
# theme assets are query-string URLs ($CFG->slasharguments = 0) and are served
css="$(printf '%s' "$dash" | grep -oE 'href="[^"]*theme/styles\.php\?[^"]*"' | sed -n '1s/href="\(.*\)"/\1/p' | sed 's/&amp;/\&/g')"
[ -n "$css" ] || { echo "!!! no styles.php link on the dashboard" >&2; exit 1; }
expect_status "$css" 200
js="$(printf '%s' "$dash" | grep -oE 'src="[^"]*lib/javascript\.php\?[^"]*"' | sed -n '1s/src="\(.*\)"/\1/p' | sed 's/&amp;/\&/g')"
expect_status "$js" 200

# 2. create a record: a course through the course form, read it back
itemid="$(curl -s -c "$jar" -b "$jar" "$BASE/course/edit.php?category=1" \
    | grep -oE 'name="summary_editor\[itemid\]" value="[0-9]+"' | grep -oE '[0-9]+"$' | tr -d '"')"
loc="$(curl -s -o /dev/null -w '%{redirect_url}' -c "$jar" -b "$jar" "$BASE/course/edit.php" \
    --data "returnto=0&returnurl=%2Fcourse%2F&id=&sesskey=$sesskey&_qf__course_edit_form=1&mform_isexpanded_id_general=1" \
    --data "category=1&visible=1&startdate%5Bday%5D=1&startdate%5Bmonth%5D=1&startdate%5Byear%5D=2026&startdate%5Bhour%5D=0&startdate%5Bminute%5D=0" \
    --data "summary_editor%5Btext%5D=&summary_editor%5Bformat%5D=1&summary_editor%5Bitemid%5D=$itemid&format=topics&numsections=4&saveanddisplay=Save+and+display" \
    --data-urlencode "fullname=ePHPm Recipe Course" --data-urlencode "shortname=EPHPM101")"
case "$loc" in
    *"/course/view.php?id="*) echo "==> course created -> $loc" ;;
    *) echo "!!! saving the course redirected to '$loc'" >&2; compose logs --tail=40 ephpm >&2; exit 1 ;;
esac
expect_body "$BASE/course/index.php" 'ePHPm Recipe Course' -c "$jar" -b "$jar"
expect_body "$loc" 'EPHPM101|ePHPm Recipe Course' -c "$jar" -b "$jar"

# 3. code outside public/ is not reachable (public/config.php is only a loader)
expect_status "$BASE/vendor/autoload.php" 404
expect_status "$BASE/info.php" 404

# 4. the admin CLI and the cron sidecar run on the embedded PHP
out="$(run_in ephpm php admin/cli/cfg.php --name=release 2>/dev/null)"
case "$out" in
    *"5."[0-9]*"(Build"*) echo "==> admin/cli/cfg.php reads the release from the database" ;;
    *) echo "!!! admin/cli/cfg.php: $out" >&2; exit 1 ;;
esac
i=0
until compose logs cron 2>/dev/null | grep -E 'Cron completed at' >/dev/null; do
    i=$((i + 1)); [ "$i" -ge 180 ] && { echo "!!! no completed cron run in the cron service" >&2; compose logs --tail=40 cron >&2; exit 1; }
    sleep 1
done
echo "==> cron service completed a cron run"
rm -f "$jar"
