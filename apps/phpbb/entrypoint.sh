#!/bin/sh
# Container entrypoint: seed the volumes, wait for the database, run phpBB's
# CLI installer on the first start (from the PHPBB_* variables), remove the
# install/ directory afterwards (phpBB refuses to serve while it exists),
# then ePHPm in the foreground.
set -eu

HTML=/var/www/html
STATE=/var/phpbb                      # config.php lives here (volume)
SEED=/usr/local/share/phpbb
cd "$HTML"

seed() { # seed <volume dir> <pristine dir>
    if [ -z "$(ls -A "$1" 2>/dev/null)" ]; then
        mkdir -p "$1" && cp -a "$2/." "$1/"
    fi
}
seed ext "$SEED/ext"
seed files "$SEED/files"
seed store "$SEED/store"
seed images/avatars/upload "$SEED/avatars"
mkdir -p cache "$STATE"
# config.php is written by the installer; keep it in the volume
[ -f "$STATE/config.php" ] || : > "$STATE/config.php"
ln -sf "$STATE/config.php" config.php

DB_HOST="${PHPBB_DB_HOST:-db}"
echo "==> waiting for database at $DB_HOST"
i=0
until php -r '
    [$h, $p] = array_pad(explode(":", $argv[1], 2), 2, 3306);
    mysqli_report(MYSQLI_REPORT_OFF);
    exit(@mysqli_connect($h, getenv("PHPBB_DB_USER") ?: "phpbb", getenv("PHPBB_DB_PASSWORD") ?: "", getenv("PHPBB_DB_NAME") ?: "phpbb", (int) $p) ? 0 : 1);
' -- "$DB_HOST" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at $DB_HOST not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

if ! grep -q "PHPBB_INSTALLED" "$STATE/config.php" 2>/dev/null; then
    if [ -d install ]; then
        echo "==> installing phpBB (install/phpbbcli.php install)"
        host="${PHPBB_DB_HOST:-db}"; port=""
        case "$host" in *:*) port="${host##*:}"; host="${host%%:*}" ;; esac
        cat > /tmp/install-config.yml <<EOF
installer:
    admin:
        name: ${PHPBB_ADMIN_USER:-admin}
        password: ${PHPBB_ADMIN_PASS:-adminadmin}
        email: ${PHPBB_ADMIN_EMAIL:-admin@example.com}
    board:
        lang: ${PHPBB_BOARD_LANG:-en}
        name: ${PHPBB_BOARD_NAME:-My Board}
        description: ${PHPBB_BOARD_DESCRIPTION:-A phpBB board on ePHPm}
    database:
        dbms: mysqli
        dbhost: ${host}
        dbport: ${port:-~}
        dbuser: ${PHPBB_DB_USER:-phpbb}
        dbpasswd: ${PHPBB_DB_PASSWORD:-}
        dbname: ${PHPBB_DB_NAME:-phpbb}
        table_prefix: ${PHPBB_TABLE_PREFIX:-phpbb_}
    email:
        enabled: false
        smtp_delivery: ~
        smtp_host: ~
        smtp_port: ~
        smtp_auth: ~
        smtp_user: ~
        smtp_pass: ~
    server:
        cookie_secure: ${PHPBB_COOKIE_SECURE:-false}
        server_protocol: ${PHPBB_SERVER_PROTOCOL:-http://}
        force_server_vars: false
        server_name: ${PHPBB_SERVER_NAME:-localhost}
        server_port: ${PHPBB_SERVER_PORT:-8080}
        script_path: ${PHPBB_SCRIPT_PATH:-/}
    extensions: []
EOF
        php install/phpbbcli.php install /tmp/install-config.yml
        rm -f /tmp/install-config.yml
        grep -q "PHPBB_INSTALLED" "$STATE/config.php" || { echo "!!! installation did not produce config.php" >&2; exit 1; }
        echo "==> phpBB installed"
    else
        echo "!!! phpBB is not installed and install/ is gone; rebuild the image or restore config.php" >&2
        exit 1
    fi
fi
# phpBB refuses to serve the board while install/ exists.
rm -rf install

exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@"
