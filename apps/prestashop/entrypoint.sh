#!/bin/sh
# Container entrypoint — the official prestashop/prestashop image's
# docker_run.sh on the embedded PHP: copy the shop into the volume on the
# first start, run the CLI installer (PS_INSTALL_AUTO=1), remove install/
# and rename the back-office folder, then ePHPm in the foreground.
set -eu

cd /var/www/prestashop
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
PS_FOLDER_ADMIN="${PS_FOLDER_ADMIN:-admin}"
PS_FOLDER_INSTALL="${PS_FOLDER_INSTALL:-install}"
export PS_FOLDER_ADMIN

if [ ! -f index.php ]; then
    echo "==> copying PrestaShop into the volume"
    cp -a /usr/src/prestashop/. /var/www/prestashop/
fi
# the front controller ships with the image; refresh it on every start
cp /usr/src/prestashop/ephpm-front.php /var/www/prestashop/ephpm-front.php

DB_SERVER="${DB_SERVER:-db}"
DB_PORT="${DB_PORT:-3306}"
echo "==> waiting for database at $DB_SERVER:$DB_PORT"
i=0
until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$DB_SERVER" "$DB_PORT" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 90 ] && { echo "!!! database at $DB_SERVER not reachable after 90 tries" >&2; exit 1; }
    sleep 2
done
MARKER=app/config/.ephpm-installed
if [ ! -f "$MARKER" ] && [ -f app/config/parameters.php ] && [ ! -d "$PS_FOLDER_INSTALL" ]; then
    # installed through the web installer (or before this marker existed)
    touch "$MARKER"
fi
if [ ! -f "$MARKER" ] && [ -f app/config/parameters.php ]; then
    echo "!!! an earlier installation did not finish (app/config/parameters.php exists, install/ is still there)." >&2
    echo "!!! Remove the volumes (docker compose down -v) and start again; see the README for why it fails on ePHPm." >&2
    exit 1
fi
if [ ! -f "$MARKER" ] && [ "${PS_INSTALL_AUTO:-0}" = "1" ]; then
    echo "==> installing PrestaShop (CLI installer)"
    # The official image's PS_INSTALL_AUTO path, same arguments.
    if ! ephpm php -d memory_limit=-1 "$PS_FOLDER_INSTALL/index_cli.php" \
        --domain="${PS_DOMAIN:-localhost:8080}" \
        --db_server="$DB_SERVER:$DB_PORT" --db_name="${DB_NAME:-prestashop}" \
        --db_user="${DB_USER:-root}" --db_password="${DB_PASSWD:-}" --prefix="${DB_PREFIX:-ps_}" \
        --firstname="${ADMIN_FIRSTNAME:-John}" --lastname="${ADMIN_LASTNAME:-Doe}" \
        --password="${ADMIN_PASSWD:-prestashop_demo}" --email="${ADMIN_MAIL:-demo@prestashop.com}" \
        --language="${PS_LANGUAGE:-en}" --country="${PS_COUNTRY:-us}" --timezone="${PS_TIMEZONE:-UTC}" \
        --all_languages="${PS_ALL_LANGUAGES:-0}" --newsletter=0 --send_email=0 \
        --ssl="${PS_ENABLE_SSL:-0}" --rewrite="${PS_REWRITE:-1}" \
        --fixtures="${PS_FIXTURES:-0}" --name="${PS_SHOP_NAME:-PrestaShop}"; then
        echo "!!! the PrestaShop installer failed (see above)" >&2
        exit 1
    fi
    touch "$MARKER"
    rm -rf "$PS_FOLDER_INSTALL"
    if [ "$PS_FOLDER_ADMIN" != "admin" ] && [ -d admin ]; then
        mv admin "$PS_FOLDER_ADMIN"
    fi
    echo "==> installed; back office at /$PS_FOLDER_ADMIN/"
elif [ ! -f "$MARKER" ]; then
    echo "==> not installed and PS_INSTALL_AUTO is not 1: open /install/ to run the web installer"
fi
echo "==> PrestaShop is ready"

exec ephpm serve --config "$CONFIG"
