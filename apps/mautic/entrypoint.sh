#!/bin/sh
# Container entrypoint: the official image's mautic_web role on the embedded
# PHP — wait for the database, install (`mautic:install`) once, migrate on
# later starts — then ePHPm in the foreground. With arguments (the cron and
# worker services) it waits for the install and runs them instead.
set -eu

cd /var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# config/, var/logs and docroot/media/{files,images} live in volumes; seed
# them when created empty.
[ -n "$(ls -A config 2>/dev/null)" ] || cp -a /usr/local/share/mautic/config/. config/
[ -n "$(ls -A docroot/media/files 2>/dev/null)" ] || cp -a /usr/local/share/mautic/media/files/. docroot/media/files/ 2>/dev/null || true
[ -n "$(ls -A docroot/media/images 2>/dev/null)" ] || cp -a /usr/local/share/mautic/media/images/. docroot/media/images/ 2>/dev/null || true
mkdir -p var/logs var/cache var/tmp docroot/media/files docroot/media/images

: "${MAUTIC_DB_HOST:?MAUTIC_DB_HOST must be set}"
: "${MAUTIC_DB_USER:?MAUTIC_DB_USER must be set}"
: "${MAUTIC_DB_PASSWORD:?MAUTIC_DB_PASSWORD must be set}"
MAUTIC_DB_PORT="${MAUTIC_DB_PORT:-3306}"
MAUTIC_DB_DATABASE="${MAUTIC_DB_DATABASE:-mautic}"

echo "==> waiting for database at $MAUTIC_DB_HOST:$MAUTIC_DB_PORT"
i=0
until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$MAUTIC_DB_HOST" "$MAUTIC_DB_PORT" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 90 ] && { echo "!!! database at $MAUTIC_DB_HOST not reachable after 90 tries" >&2; exit 1; }
    sleep 2
done

installed() {
    [ -f config/local.php ] && ephpm php -r 'include $argv[1]; exit(!empty($parameters["db_driver"]) && !empty($parameters["site_url"]) ? 0 : 1);' config/local.php
}

if [ "$#" -gt 0 ]; then
    until installed; do echo "==> waiting for the web container to install Mautic"; sleep 5; done
    exec "$@"
fi

rm -rf var/cache/*
if installed; then
    echo "==> installed; running migrations"
    mautic doctrine:migrations:migrate --no-interaction
else
    if [ -z "${MAUTIC_ADMIN_EMAIL:-}" ] || [ -z "${MAUTIC_ADMIN_PASSWORD:-}" ]; then
        echo "==> not installed and MAUTIC_ADMIN_EMAIL/MAUTIC_ADMIN_PASSWORD unset: open ${MAUTIC_SITE_URL:-http://localhost:8080}/installer"
    else
        echo "==> installing (schema + admin)"
        mautic mautic:install "${MAUTIC_SITE_URL:-http://localhost:8080}" --no-interaction --force \
            --db_driver=pdo_mysql --db_host="$MAUTIC_DB_HOST" --db_port="$MAUTIC_DB_PORT" \
            --db_name="$MAUTIC_DB_DATABASE" --db_user="$MAUTIC_DB_USER" --db_password="$MAUTIC_DB_PASSWORD" \
            --admin_email="$MAUTIC_ADMIN_EMAIL" --admin_password="$MAUTIC_ADMIN_PASSWORD" \
            --admin_username="${MAUTIC_ADMIN_USERNAME:-admin}" \
            --admin_firstname="${MAUTIC_ADMIN_FIRSTNAME:-Admin}" --admin_lastname="${MAUTIC_ADMIN_LASTNAME:-User}"
    fi
fi
mautic cache:warmup --no-interaction >/dev/null 2>&1 || true
echo "==> Mautic is ready"

exec ephpm serve --config "$CONFIG"
