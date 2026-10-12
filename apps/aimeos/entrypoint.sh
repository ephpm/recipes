#!/bin/sh
# Container entrypoint: what `composer create-project aimeos/aimeos` does
# interactively (APP_KEY, migrate, aimeos:setup, admin account), then ePHPm
# in the foreground.
#
#   entrypoint.sh                 -> setup, then ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> same, extra args to `ephpm serve`
#   entrypoint.sh <command...>    -> wait for the DB, then run <command>
#                                    (the `jobs` sidecar; `docker compose run --rm ephpm ephpm php artisan ...`)
set -eu
cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# storage/ is a volume: seed the directory layout when it starts out empty.
[ -d storage/framework ] || cp -a /usr/local/share/aimeos/storage/. storage/
mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs storage/tmp storage/app/public

case "${1:-}" in ""|-*) SERVE=1 ;; *) SERVE=0 ;; esac

# APP_KEY: from the environment, else generated once into the storage volume
# by the web container (a sidecar sharing the volume waits for it).
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
    exit(@mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "aimeos", (int) (getenv("DB_PORT") ?: 3306)) ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

[ "$SERVE" = 1 ] || exec "$@"

echo "==> migrating"
ephpm php artisan migrate --force --no-interaction

# aimeos:setup creates/updates the shop tables and default data; run on every
# start (it is idempotent, and it is the upgrade step). The demo catalogue is
# added once, on the first setup, unless AIMEOS_DEMO=0.
if [ ! -f storage/.aimeos_setup_done ] && [ "${AIMEOS_DEMO:-1}" = "1" ]; then
    echo "==> aimeos:setup (with demo data)"
    ephpm php artisan aimeos:setup --option=setup/default/demo:1
else
    echo "==> aimeos:setup"
    ephpm php artisan aimeos:setup
fi
touch storage/.aimeos_setup_done

# First administrator (creates or updates the account; idempotent).
if [ -n "${AIMEOS_ADMIN_EMAIL:-}" ] && [ -n "${AIMEOS_ADMIN_PASSWORD:-}" ]; then
    ephpm php artisan aimeos:account "$AIMEOS_ADMIN_EMAIL" --password="$AIMEOS_ADMIN_PASSWORD" --super --admin
fi

ephpm php artisan storage:link >/dev/null 2>&1 || true
ephpm php artisan optimize >/dev/null

exec ephpm serve --config "$CONFIG" "$@"
