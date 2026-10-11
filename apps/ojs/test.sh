#!/usr/bin/env bash
# Smoke test: complete OJS's installer with the same POST the official
# image's PKP_CLI_INSTALL mode sends (schema + site admin), log in through
# the login form, and open the site administration page. Runs against the
# MariaDB compose file (OJS's installer emits MySQL-specific DDL; no
# embedded-database variant).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28502
recipe_init ojs

export PKP_BASE_URL="$BASE"

# OJS renders its CSRF token into forms: pull it out of a page.
token() { grep -o "<input[^>]*name=\"$2\"[^>]*>" "$1" | head -n1 | sed 's/.*value="\([^"]*\)".*/\1/'; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # not installed: every page shows the installer (served through the
    # PATH_INFO front controller — /index.php/index/install)
    wait_http "$BASE/index.php/index/en/install" 200 300
    expect_body "$BASE/index.php/index/en/install" "OJS Installation"

    # 1. the installer POST (what pkp/containers' pkp-cli-install sends)
    #    (creating the schema takes a minute or two — longer than the
    #    harness's 30 s curl limit, so this one request has its own)
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 600 "$BASE/index.php/index/en/install/install" \
        --data "installing=0&installLanguage=en&locale=en&additionalLocales%5B%5D=en&timeZone=UTC&adminUsername=admin&adminPassword=recipe-pass-123&adminPassword2=recipe-pass-123&adminEmail=admin%40example.com&filesDir=%2Fvar%2Fwww%2Ffiles&databaseDriver=mysqli&databaseHost=db&databaseUsername=pkp&databasePassword=changeMePlease&databaseName=pkp&oaiRepositoryId=ojs.recipe&enableBeacon=0" || true)"
    [ "$code" = 200 ] || { echo "!!! installer POST -> $code (wanted 200)" >&2; compose logs --tail=60 ephpm >&2; return 1; }
    echo "==> installer POST -> 200"
    run_in ephpm grep -q "^installed = On" /var/www/config/config.inc.php \
        || { echo "!!! config.inc.php does not say installed = On" >&2; compose logs --tail=60 ephpm >&2; return 1; }
    echo "==> installed = On"

    # 2. real workflow: log in and open the site administration
    local jar page; jar="$(cookie_jar)"; page="$(native_path "$(mktemp)")"
    curl -s -c "$jar" -o "$page" "$BASE/index.php/index/login"
    expect_status "$BASE/index.php/index/login/signIn" 302 -b "$jar" -c "$jar" -e "$BASE/index.php/index/login" \
        --data-urlencode "csrfToken=$(token "$page" csrfToken)" \
        --data "username=admin&password=recipe-pass-123&remember=0"
    expect_body "$BASE/index.php/index/admin" "Hosted Journals" -L -b "$jar" -c "$jar"

    # 3. the CLI tools run on the embedded PHP
    run_in ephpm ephpm php /var/www/html/tools/upgrade.php check | grep -iE "version|up to date|Code version" >/dev/null \
        || { echo "!!! tools/upgrade.php not working" >&2; return 1; }
    echo "==> OJS CLI tools work"

    compose down -v --remove-orphans
}

run_variant compose.yml
