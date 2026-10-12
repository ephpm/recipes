#!/bin/sh
# Container entrypoint: seed the volumes, restore .env (it holds the two
# secrets the app generates), wait for the database, provision the secrets
# (`spark env:provision`, as upstream's compose command does), then ePHPm
# in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

APP=/app
SEED=/usr/local/share/ospos
cd "$APP"

for d in backup cache debugbar logs session uploads; do
    [ -d "writable/$d" ] || cp -a "$SEED/writable/$d" writable/
done
[ -e writable/index.html ] || cp -a "$SEED/writable/index.html" writable/
[ -d public/uploads/item_pics ] || cp -a "$SEED/uploads/." public/uploads/

# .env is rewritten by the app (encryption.key, throttle.key). It lives in
# the writable volume and is copied into place on every start; upstream
# bind-mounts a host file instead (a symlink would be replaced by the app's
# atomic rename).
[ -f writable/.env ] || cp "$SEED/.env" writable/.env
cp writable/.env .env

echo "==> waiting for database at ${MYSQL_HOST_NAME:-db}"
i=0
until php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    exit(@mysqli_connect(getenv("MYSQL_HOST_NAME") ?: "db", getenv("MYSQL_USERNAME") ?: "admin", getenv("MYSQL_PASSWORD") ?: "", getenv("MYSQL_DB_NAME") ?: "ospos") ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

# Schema first (a fresh database or an upgraded image), then the secrets:
# env:provision reads the app config table, so on an empty database it
# fails unless the migrations ran (upstream's compose seeds the database
# from an SQL dump instead).
php spark migrate --all --no-ansi
php spark env:provision --no-ansi
cp .env writable/.env

case "${1:-}" in
    ""|-*) exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@" ;;
    *) exec "$@" ;;
esac
