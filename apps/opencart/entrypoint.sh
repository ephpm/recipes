#!/bin/sh
# Container entrypoint: copy OpenCart into the volume on the first start,
# run its CLI installer (install/cli_install.php) once, remove install/,
# then ePHPm in the foreground.
set -eu

cd /var/www/opencart
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

if [ ! -f index.php ]; then
    echo "==> copying OpenCart into the volume"
    cp -a /usr/src/opencart/. /var/www/opencart/
fi

DB_HOSTNAME="${DB_HOSTNAME:-db}"
DB_PORT="${DB_PORT:-3306}"
echo "==> waiting for database at $DB_HOSTNAME:$DB_PORT"
i=0
until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$DB_HOSTNAME" "$DB_PORT" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 90 ] && { echo "!!! database at $DB_HOSTNAME not reachable after 90 tries" >&2; exit 1; }
    sleep 2
done

if [ -d install ]; then
    if [ -n "${OPENCART_ADMIN_EMAIL:-}" ] && [ -n "${OPENCART_ADMIN_PASSWORD:-}" ]; then
        echo "==> installing OpenCart (CLI installer)"
        [ -f config.php ] || cp config-dist.php config.php
        [ -f admin/config.php ] || cp admin/config-dist.php admin/config.php
        out="$(ephpm php install/cli_install.php install \
            --username "${OPENCART_ADMIN_USERNAME:-admin}" \
            --email "$OPENCART_ADMIN_EMAIL" --password "$OPENCART_ADMIN_PASSWORD" \
            --http_server "${OPENCART_URL:-http://localhost:8080}/" \
            --language en-gb --db_driver mysqli \
            --db_hostname "$DB_HOSTNAME" --db_port "$DB_PORT" \
            --db_username "${DB_USERNAME:-opencart}" --db_password "${DB_PASSWORD:-}" \
            --db_database "${DB_DATABASE:-opencart}" --db_prefix "${DB_PREFIX:-oc_}" 2>&1)" || true
        echo "$out"
        case "$out" in
            *SUCCESS*) ;;
            *) echo "!!! the OpenCart installer failed (see above)" >&2; exit 1 ;;
        esac
        rm -rf install
    else
        echo "==> not installed and OPENCART_ADMIN_EMAIL/OPENCART_ADMIN_PASSWORD unset: open /install/ for the web installer"
    fi
fi
echo "==> OpenCart is ready"

exec ephpm serve --config "$CONFIG"
