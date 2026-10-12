#!/bin/sh
# Container entrypoint: INSTALL.md steps 3-7 (APP_KEY, migrate, storage:link,
# first administrator), then ePHPm in the foreground.
#
#   entrypoint.sh                 -> setup, then ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> same, extra args to `ephpm serve`
#   entrypoint.sh <command...>    -> wait for APP_KEY + the DB, then run <command>
#                                    (the worker / scheduler sidecars)
set -eu
cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
case "${1:-}" in ""|-*) SERVE=1 ;; *) SERVE=0 ;; esac

# storage/ is a volume: seed the layout the release ships when it is empty.
[ -d storage/framework ] || cp -a /usr/local/share/projectsend/storage/. storage/
mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs \
         storage/app/files storage/app/public storage/app/private storage/app/uploads-tmp

# APP_KEY: from the environment, else generated once into the storage volume
# (the official image keeps it there too) by the web container; sidecars
# sharing the volume wait for it.
if [ -z "${APP_KEY:-}" ]; then
    if [ "$SERVE" = 0 ]; then
        i=0
        until [ -s storage/.app_key ]; do
            i=$((i + 1)); [ "$i" -ge 300 ] && { echo "!!! no storage/.app_key after 300s" >&2; exit 1; }
            sleep 1
        done
    fi
    if [ ! -s storage/.app_key ]; then
        echo "base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')" > storage/.app_key
        echo "==> generated APP_KEY into the storage volume"
    fi
    APP_KEY="$(cat storage/.app_key)"
    export APP_KEY
fi

echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
i=0
until ephpm php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    exit(@mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "projectsend", (int) (getenv("DB_PORT") ?: 3306)) ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 90 ] && { echo "!!! database not reachable after 90 tries" >&2; exit 1; }
    sleep 2
done

if [ "$SERVE" = 0 ]; then
    # sidecars: wait until the web container has migrated
    i=0
    until ephpm php artisan migrate:status --no-interaction >/dev/null 2>&1; do
        i=$((i + 1)); [ "$i" -ge 150 ] && break
        sleep 2
    done
    exec "$@"
fi

echo "==> migrating"
ephpm php artisan migrate --force --no-interaction
ephpm php artisan storage:link --force >/dev/null 2>&1 || true

# First administrator, when PROJECTSEND_ADMIN_EMAIL/_PASSWORD are given and no
# staff account exists yet (otherwise the browser shows the setup screen).
if [ -n "${PROJECTSEND_ADMIN_EMAIL:-}" ] && [ -n "${PROJECTSEND_ADMIN_PASSWORD:-}" ]; then
    ephpm php artisan projectsend:admin --if-none --no-interaction \
        --name="${PROJECTSEND_ADMIN_NAME:-Administrator}" \
        --email="$PROJECTSEND_ADMIN_EMAIL" --password="$PROJECTSEND_ADMIN_PASSWORD"
fi

ephpm php artisan optimize >/dev/null

exec ephpm serve --config "$CONFIG" "$@"
