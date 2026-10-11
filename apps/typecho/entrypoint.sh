#!/bin/sh
# Container entrypoint: install Typecho on the first start with its own CLI
# installer (`php install.php`, driven by the TYPECHO_* variables — the same
# ones the joyqi/typecho image uses), then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

APP=/app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$APP"
mkdir -p "$APP/usr/uploads"

case "${TYPECHO_DB_ADAPTER:-Pdo_Mysql}" in
    *Mysql*)
        echo "==> waiting for database at ${TYPECHO_DB_HOST:-db}:${TYPECHO_DB_PORT:-3306}"
        i=0
        until ephpm php -r '
            mysqli_report(MYSQLI_REPORT_OFF);
            exit(@mysqli_connect(getenv("TYPECHO_DB_HOST") ?: "db", getenv("TYPECHO_DB_USER") ?: "root", getenv("TYPECHO_DB_PASSWORD") ?: "", getenv("TYPECHO_DB_DATABASE") ?: "typecho", (int) (getenv("TYPECHO_DB_PORT") ?: 3306)) ? 0 : 1);
        ' 2>/dev/null; do
            i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
            sleep 2
        done
        ;;
esac

# config.inc.php is kept in the data volume and copied into the web root
# (a symlink would not do: it derives the site root from dirname(__FILE__)).
if [ -s /data/config.inc.php ]; then
    cp /data/config.inc.php "$APP/config.inc.php"
elif [ "${TYPECHO_INSTALL:-1}" = "1" ]; then
    : "${TYPECHO_SITE_URL:?TYPECHO_SITE_URL must be set (the public URL of the blog)}"
    : "${TYPECHO_USER_PASSWORD:?TYPECHO_USER_PASSWORD must be set for the first start}"
    echo "==> installing Typecho"
    rm -f "$APP/config.inc.php"
    ephpm php install.php
    cp "$APP/config.inc.php" /data/config.inc.php
fi

case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
