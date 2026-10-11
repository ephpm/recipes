#!/usr/bin/env bash
# Smoke test: the container installs Drupal with Drush on first start (plus
# the page/article content-type recipes); then log in through /user/login,
# create an article through /node/add/article and read it back (node page
# and clean URL alias-less path), check private files, and run Drush on the
# embedded PHP.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28607
recipe_init drupal
export DRUPAL_ADMIN_PASSWORD="recipe-admin-pass-31"

# load_form URL — GET a form page (with the jar) into $form; field NAME prints a hidden value
load_form() { form="$(curl -s --max-time 60 -c "$jar" -b "$jar" "$1")"; }
field() { printf '%s' "$form" | grep -oE "name=\"$1\" value=\"[^\"]*\"" | sed -n '1s/.*value="\([^"]*\)"/\1/p'; }

compose_up
wait_http "$BASE/user/login" 200 600                       # after drush site:install
expect_body "$BASE/" 'Drupal on ePHPm'

# 1. real workflow: log in through the login form
jar="$(cookie_jar)"
load_form "$BASE/user/login"
[ -n "$(field form_build_id)" ] || { echo "!!! no form_build_id on /user/login" >&2; exit 1; }
expect_status "$BASE/user/login" 303 -c "$jar" -b "$jar" \
    --data-urlencode "form_build_id=$(field form_build_id)" \
    --data "form_id=user_login_form&name=admin&op=Log+in" --data-urlencode "pass=$DRUPAL_ADMIN_PASSWORD"
expect_body "$BASE/user/1" 'user/logout' -c "$jar" -b "$jar"

# 2. create a record: an article through the node form, read it back
load_form "$BASE/node/add/article"
[ -n "$(field form_token)" ] || { echo "!!! no form_token on /node/add/article" >&2; exit 1; }
loc="$(curl -s -o /dev/null -w '%{redirect_url}' -c "$jar" -b "$jar" "$BASE/node/add/article" \
    --data-urlencode "form_build_id=$(field form_build_id)" --data-urlencode "form_token=$(field form_token)" \
    --data "form_id=node_article_form&status%5Bvalue%5D=1&op=Save" \
    --data-urlencode "title[0][value]=Hello from ePHPm" \
    --data-urlencode "body[0][value]=<p>Written by the recipe smoke test.</p>" \
    --data-urlencode "body[0][format]=basic_html")"
case "$loc" in
    "$BASE/node/"[0-9]*) echo "==> article created -> $loc" ;;
    *) echo "!!! saving the article redirected to '$loc'" >&2; compose logs --tail=60 ephpm >&2; exit 1 ;;
esac
expect_body "$loc" 'Written by the recipe smoke test'           # anonymous view
expect_body "$BASE/index.php/node/${loc##*/}" 'Written by the recipe smoke test'

# 3. static assets, and what web/.htaccess keeps private
expect_status "$BASE/core/misc/drupal.js" 200
expect_status "$BASE/sites/default/settings.php" 403
expect_status "$BASE/sites/default/default.services.yml" 403
expect_status "$BASE/info.php" 404

# 4. Drush on the embedded PHP, against the same database
out="$(run_in ephpm drush status --field=bootstrap 2>&1)"
case "$out" in
    *Successful*) echo "==> drush status: bootstrap successful" ;;
    *) echo "!!! drush status: $out" >&2; exit 1 ;;
esac
out="$(run_in ephpm drush php:eval "echo \Drupal::entityTypeManager()->getStorage('node')->load(${loc##*/})->label();" 2>&1)"
case "$out" in
    *"Hello from ePHPm"*) echo "==> drush php:eval loads the article" ;;
    *) echo "!!! drush php:eval: $out" >&2; exit 1 ;;
esac
rm -f "$jar"
