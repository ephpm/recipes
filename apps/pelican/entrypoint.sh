#!/bin/sh
# Container entrypoint: first-run setup (what the official entrypoint does
# once APP_INSTALLED=true, plus the admin user the web installer would
# create), then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
#                                    (the scheduler and queue services)
set -eu

APP=/app
DATA=/pelican-data
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

mkdir -p "$DATA/database" "$DATA/storage/avatars" "$DATA/storage/fonts" "$DATA/storage/icons" "$DATA/plugins" \
    "$APP/storage/framework/cache" "$APP/storage/framework/sessions" "$APP/storage/framework/views" "$APP/storage/logs"

# .env lives in the data volume (the official image does the same): the
# server seeds it with a generated APP_KEY; command containers wait for it.
case "${1:-}" in
    ""|-*)
        if [ ! -f "$DATA/.env" ]; then
            key="${APP_KEY:-base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')}"
            printf 'APP_KEY=%s\nAPP_INSTALLED=true\n' "$key" > "$DATA/.env"
            echo "==> generated APP_KEY into /pelican-data/.env"
        fi
        ;;
    *)
        i=0
        until [ -f "$DATA/.ephpm-installed" ]; do
            i=$((i + 1)); [ "$i" -ge 240 ] && { echo "!!! the server did not finish installing after 240s" >&2; exit 1; }
            sleep 1
        done
        ;;
esac

# Wait for an external database when one is configured (SQLite needs none).
if [ "${DB_CONNECTION:-sqlite}" != "sqlite" ]; then
    echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
    i=0
    until ephpm php -r '
        mysqli_report(MYSQLI_REPORT_OFF);
        $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "panel", (int) (getenv("DB_PORT") ?: 3306));
        exit($c ? 0 : 1);
    ' 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
        sleep 2
    done
else
    [ -f "$DATA/database/database.sqlite" ] || touch "$DATA/database/database.sqlite"
fi

case "${1:-}" in
    ""|-*)
        echo "==> running database migrations"
        ephpm php artisan migrate --force --no-interaction
        if [ ! -f "$DATA/.ephpm-installed" ]; then
            # The admin account the web installer would create.
            echo "==> creating the admin user (${PELICAN_ADMIN_EMAIL:-admin@example.com})"
            ephpm php artisan p:user:make --admin=1 \
                --email="${PELICAN_ADMIN_EMAIL:-admin@example.com}" \
                --username="${PELICAN_ADMIN_USERNAME:-admin}" \
                --password="${PELICAN_ADMIN_PASSWORD:-changeme}"
            touch "$DATA/.ephpm-installed"
        fi
        ephpm php artisan p:plugin:composer >/dev/null 2>&1 || true
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
