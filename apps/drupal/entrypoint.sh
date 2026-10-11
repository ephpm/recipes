#!/bin/bash
# Container entrypoint: seed web/sites (settings.php, files/) into its volume,
# wait for the database, install Drupal with Drush on the first start when
# DRUPAL_ADMIN_PASSWORD is set (otherwise the web installer at /core/install.php
# runs, as in the official image), then ePHPm in the foreground.
set -euo pipefail

ROOT=/opt/drupal
SITES=$ROOT/web/sites
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$ROOT"

# web/sites is a volume: seed what the project ships when it is empty.
[ -e "$SITES/default/default.settings.php" ] || cp -a /usr/local/share/drupal-sites/. "$SITES/"
mkdir -p "$SITES/default/files" "$ROOT/private"

installed() {
    [ -f "$SITES/default/settings.php" ] && grep -q "^\$databases\['default'\]" "$SITES/default/settings.php"
}

if [ -n "${DRUPAL_DB_HOST:-}" ]; then
    echo "==> waiting for database at ${DRUPAL_DB_HOST}:${DRUPAL_DB_PORT:-3306}"
    i=0
    until ephpm php -r '
        $d = getenv("DRUPAL_DB_DRIVER") ?: "mysql";
        $dsn = ($d === "pgsql" ? "pgsql" : "mysql") . ":host=" . getenv("DRUPAL_DB_HOST") . ";port=" . (getenv("DRUPAL_DB_PORT") ?: ($d === "pgsql" ? 5432 : 3306)) . ";dbname=" . getenv("DRUPAL_DB_NAME");
        try { new PDO($dsn, getenv("DRUPAL_DB_USER"), getenv("DRUPAL_DB_PASSWORD")); } catch (Throwable $e) { exit(1); }
    ' 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
        sleep 2
    done
fi

if ! installed && [ -n "${DRUPAL_ADMIN_PASSWORD:-}" ] && [ -n "${DRUPAL_DB_HOST:-}" ]; then
    echo "==> installing Drupal (drush site:install ${DRUPAL_PROFILE:-standard})"
    [ -f "$SITES/default/settings.php" ] || cp "$SITES/default/default.settings.php" "$SITES/default/settings.php"
    # private files outside the web root (Drupal's recommended setup)
    grep -q "^\$settings\['file_private_path'\]" "$SITES/default/settings.php" || \
        printf "\n\$settings['file_private_path'] = '%s/private';\n" "$ROOT" >> "$SITES/default/settings.php"
    driver="${DRUPAL_DB_DRIVER:-mysql}"
    port="${DRUPAL_DB_PORT:-$([ "$driver" = pgsql ] && echo 5432 || echo 3306)}"
    db_url="$(ephpm php -r 'echo $argv[1], "://", rawurlencode($argv[2]), ":", rawurlencode($argv[3]), "@", $argv[4], ":", $argv[5], "/", $argv[6];' -- \
        "$driver" "$DRUPAL_DB_USER" "$DRUPAL_DB_PASSWORD" "$DRUPAL_DB_HOST" "$port" "$DRUPAL_DB_NAME")"
    drush site:install "${DRUPAL_PROFILE:-standard}" --yes \
        --db-url="$db_url" \
        --site-name="${DRUPAL_SITE_NAME:-Drupal on ePHPm}" \
        --site-mail="${DRUPAL_SITE_MAIL:-admin@example.com}" \
        --account-name="${DRUPAL_ADMIN_USER:-admin}" \
        --account-mail="${DRUPAL_ADMIN_MAIL:-admin@example.com}" \
        --account-pass="$DRUPAL_ADMIN_PASSWORD" \
        --locale="${DRUPAL_LOCALE:-en}"
    # Since Drupal 11.4 the standard profile no longer ships content types;
    # they are core recipes. Apply the usual two (DRUPAL_RECIPES, space
    # separated, "" for none).
    for r in ${DRUPAL_RECIPES-core/recipes/page_content_type core/recipes/article_content_type}; do
        echo "==> applying recipe $r"
        drush recipe "$r" --no-interaction
    done
    drush cache:rebuild
    echo "==> Drupal installed"
elif installed; then
    # pending schema/config updates after an image upgrade
    drush updatedb --yes || echo "!!! drush updatedb failed; run it by hand" >&2
fi

# Behind a reverse proxy Drupal needs the proxy's address in settings.php
# ($settings['reverse_proxy']); trusted host patterns are left to you.
exec ephpm serve --config "$CONFIG" "$@"
