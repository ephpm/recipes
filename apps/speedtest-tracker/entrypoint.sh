#!/bin/sh
# Container entrypoint: first-run setup (APP_KEY, SQLite file, migrations —
# which seed the admin from ADMIN_*), then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
#                                    (the scheduler and queue services)
set -eu

APP=/app
DATA=/data
STORAGE=$APP/storage
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

for d in app/public framework/cache framework/sessions framework/views logs; do
    mkdir -p "$STORAGE/$d"
done

# .env lives in the data volume (the linuxserver image keeps it in /config
# the same way) and /app/.env points at it; the server seeds it with a
# generated APP_KEY, command containers wait for the seed.
case "${1:-}" in
    ""|-*)
        if [ ! -f "$DATA/.env" ]; then
            key="${APP_KEY:-base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')}"
            printf 'APP_KEY=%s\n' "$key" > "$DATA/.env"
            echo "==> generated APP_KEY into /data/.env"
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
ln -sfn "$DATA/.env" "$APP/.env"

# SQLite by default (upstream's default); wait for MySQL/Postgres when configured.
case "${DB_CONNECTION:-sqlite}" in
    sqlite)
        [ -f "${DB_DATABASE:-$DATA/database.sqlite}" ] || touch "${DB_DATABASE:-$DATA/database.sqlite}"
        ;;
    mysql|mariadb)
        echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
        i=0
        until ephpm php -r '
            mysqli_report(MYSQLI_REPORT_OFF);
            $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "speedtest_tracker", (int) (getenv("DB_PORT") ?: 3306));
            exit($c ? 0 : 1);
        ' 2>/dev/null; do
            i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
            sleep 2
        done
        ;;
esac

case "${1:-}" in
    ""|-*)
        # What the linuxserver init runs: migrate (the users migration seeds
        # the admin from ADMIN_NAME / ADMIN_EMAIL / ADMIN_PASSWORD on a fresh
        # database) and Filament's component cache.
        echo "==> running database migrations"
        ephpm php artisan migrate --force --no-interaction
        ephpm php artisan filament:cache-components >/dev/null 2>&1 || true
        touch "$DATA/.ephpm-installed"
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
