#!/bin/sh
# Container entrypoint: seed the config volume, wait for the database, run
# Ampache's CLI installer on the first start (database + ampache.cfg.php)
# and create the admin user, then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh cron            -> run Ampache's cron process every hour
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

APP=/app
cd "$APP"
[ -n "$(ls -A config 2>/dev/null)" ] || cp -a /usr/local/share/ampache/config/. config/
CFG=config/ampache.cfg.php

if [ "${1:-}" = "cron" ]; then
    until [ -f "$CFG" ]; do sleep 5; done
    echo "==> running bin/cli run:cronProcess every hour"
    while :; do
        php bin/cli run:cronProcess || echo "cron process exited with $?" >&2
        sleep 3600
    done
fi

DB_HOST="${AMPACHE_DB_HOST:-db}"
echo "==> waiting for database at $DB_HOST:${AMPACHE_DB_PORT:-3306}"
i=0
until php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    exit(@mysqli_connect(getenv("AMPACHE_DB_HOST") ?: "db", getenv("AMPACHE_DB_ADMIN_USER") ?: "root", getenv("AMPACHE_DB_ADMIN_PASSWORD") ?: "", "", (int) (getenv("AMPACHE_DB_PORT") ?: 3306)) ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

if [ ! -f "$CFG" ]; then
    echo "==> installing Ampache (bin/installer install)"
    # The installer connects with an administrative account to create the
    # database and the Ampache user, like the web installer.
    php bin/installer install \
        --dbhost "$DB_HOST" --dbport "${AMPACHE_DB_PORT:-3306}" \
        --dbuser "${AMPACHE_DB_ADMIN_USER:-root}" --dbpassword "${AMPACHE_DB_ADMIN_PASSWORD:-}" \
        --dbname "${AMPACHE_DB_NAME:-ampache}" \
        --ampachedbuser "${AMPACHE_DB_USER:-ampache}" --ampachedbpassword "${AMPACHE_DB_PASSWORD:-ampache}" \
        --webpath "${AMPACHE_WEB_PATH:-}"
    [ -f "$CFG" ] || { echo "!!! the installer did not write $CFG" >&2; exit 1; }
    if [ -n "${AMPACHE_ADMIN_PASSWORD:-}" ]; then
        php bin/cli admin:addUser "${AMPACHE_ADMIN_USER:-admin}" \
            --password "$AMPACHE_ADMIN_PASSWORD" --email "${AMPACHE_ADMIN_EMAIL:-}" --level 100
    fi
    echo "==> Ampache installed"
else
    # an upgraded image: apply database updates
    php bin/cli admin:updateDatabase --execute || true
fi

# Ampache builds its absolute URLs from SERVER_NAME and SERVER_PORT unless
# http_host / http_port are configured. ePHPm reports the port it listens on
# (8080), not the published one (issues/moodle.md), so pin them from the
# environment on every start.
setcfg() { # setcfg key value — set (or uncomment) a top-level key in ampache.cfg.php
    if grep -qE "^;?$1 = " "$CFG"; then
        sed -i -E "s|^;?$1 = .*|$1 = \"$2\"|" "$CFG"
    else
        printf '%s = "%s"\n' "$1" "$2" >> "$CFG"
    fi
}
[ -z "${AMPACHE_HTTP_HOST:-}" ] || setcfg http_host "$AMPACHE_HTTP_HOST"
[ -z "${AMPACHE_HTTP_PORT:-}" ] || setcfg http_port "$AMPACHE_HTTP_PORT"

case "${1:-}" in
    ""|-*) exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@" ;;
    *) exec "$@" ;;
esac
