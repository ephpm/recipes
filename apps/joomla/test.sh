#!/usr/bin/env bash
# Smoke test: the container installs Joomla with installation/joomla.php on
# first start; then log in to the administrator through its login form,
# create an article through the article editor, read it back in the admin
# list and on the site (plain and SEF URLs, with and without index.php),
# and run cli/joomla.php on the embedded PHP.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28606
recipe_init joomla
export JOOMLA_ADMIN_PASSWORD="recipe-admin-pass-77"

# token FILE-CONTENT — Joomla's form token is a hidden input named by a 32-hex hash with value 1
token() { printf '%s' "$1" | grep -oE 'name="[0-9a-f]{32}" value="1"' | sed -n '1s/name="\([0-9a-f]*\)".*/\1/p'; }

compose_up
wait_http "$BASE/" 200 300                                  # after the CLI install
expect_body "$BASE/" 'Joomla on ePHPm'

# 1. real workflow: log in to the administrator
jar="$(cookie_jar)"
page="$(curl -s -c "$jar" -b "$jar" "$BASE/administrator/")"
tok="$(token "$page")"
[ -n "$tok" ] || { echo "!!! no form token on the administrator login" >&2; exit 1; }
expect_status "$BASE/administrator/index.php" 303 -c "$jar" -b "$jar" \
    --data "option=com_login&task=login&return=aW5kZXgucGhw&username=admin&$tok=1" \
    --data-urlencode "passwd=$JOOMLA_ADMIN_PASSWORD"
expect_body "$BASE/administrator/index.php" 'task=logout|com_login&amp;task=logout' -c "$jar" -b "$jar"

# 2. create a record: an article through the editor (task=article.add → save)
page="$(curl -s -L -c "$jar" -b "$jar" "$BASE/administrator/index.php?option=com_content&task=article.add")"
tok="$(token "$page")"
[ -n "$tok" ] || { echo "!!! no form token on the article editor" >&2; exit 1; }
expect_status "$BASE/administrator/index.php?option=com_content&layout=edit&id=0" 303 -c "$jar" -b "$jar" \
    --data-urlencode "jform[title]=Hello from ePHPm" \
    --data-urlencode "jform[articletext]=<p>Written by the recipe smoke test.</p>" \
    --data "jform[catid]=2&jform[state]=1&jform[language]=*&jform[access]=1&task=article.save&$tok=1"
expect_body "$BASE/administrator/index.php?option=com_content&view=articles" 'Hello from ePHPm' -c "$jar" -b "$jar"
#    … and read it on the site: query-string URL, SEF URL through index.php,
#    and the rewritten SEF URL (no index.php — [server] fallback)
expect_body "$BASE/index.php?option=com_content&view=article&id=1&catid=2" 'Written by the recipe smoke test'
expect_body "$BASE/index.php/component/content/article/hello-from-ephpm?catid=2" 'Written by the recipe smoke test'
expect_body "$BASE/component/content/article/hello-from-ephpm?catid=2" 'Written by the recipe smoke test'

# 3. the CLI runs on the embedded PHP
out="$(run_in ephpm php cli/joomla.php config:get sitename 2>&1)"
case "$out" in
    *"Joomla on ePHPm"*) echo "==> cli/joomla.php config:get sitename" ;;
    *) echo "!!! cli/joomla.php config:get failed: $out" >&2; exit 1 ;;
esac

# 4. private files are not served; the base image's fixtures are gone
expect_status "$BASE/configuration.php" 403
expect_status "$BASE/administrator/logs/" 403
expect_status "$BASE/info.php" 404
rm -f "$jar"
