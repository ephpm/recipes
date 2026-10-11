#!/bin/sh
# First-run setup, then ePHPm in the foreground.
set -eu
cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# storage/ is a volume: make sure the framework's directories exist.
mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs storage/app/public

# APP_KEY: use the one from the environment, else generate once into the
# storage volume so it survives container restarts.
if [ -z "${APP_KEY:-}" ]; then
    if [ ! -f storage/.app_key ]; then
        ephpm php artisan key:generate --show > storage/.app_key
    fi
    APP_KEY="$(cat storage/.app_key)"
    export APP_KEY
fi

# Wait for an external database (the embedded one starts with the server).
case "${DB_HOST:-127.0.0.1}" in
    127.0.0.1|localhost) ;;
    *)
        echo "==> waiting for database at ${DB_HOST}:${DB_PORT:-3306}"
        i=0
        until ephpm php -r '
            mysqli_report(MYSQLI_REPORT_OFF);
            exit(@mysqli_connect(getenv("DB_HOST"), getenv("DB_USERNAME"), getenv("DB_PASSWORD"), getenv("DB_DATABASE"), (int) (getenv("DB_PORT") ?: 3306)) ? 0 : 1);
        ' 2>/dev/null; do
            i=$((i + 1))
            [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
            sleep 2
        done
        ;;
esac

if [ "${SKIP_MIGRATE:-0}" != "1" ]; then
    # The embedded database only accepts connections once the server is up,
    # so migrations against it run from a background step after startup.
    case "${DB_HOST:-127.0.0.1}" in
        127.0.0.1|localhost)
            ( i=0
              until ephpm php -r 'mysqli_report(MYSQLI_REPORT_OFF); exit(@mysqli_connect("127.0.0.1", "root", "", "laravel", 3306) ? 0 : 1);' 2>/dev/null; do
                  i=$((i + 1)); [ "$i" -ge 60 ] && exit 1; sleep 1
              done
              echo "==> migrating (embedded database)"
              ephpm php artisan migrate --force --no-interaction ) &
            ;;
        *)
            echo "==> migrating"
            ephpm php artisan migrate --force --no-interaction
            ;;
    esac
fi

ephpm php artisan storage:link >/dev/null 2>&1 || true
ephpm php artisan optimize >/dev/null

exec ephpm serve --config "$CONFIG" "$@"
