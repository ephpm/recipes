#!/bin/sh
# Container entrypoint: what `composer setup` does (APP_KEY, migrate, seed the
# demo data once), then ePHPm in the foreground.
#
#   entrypoint.sh                 -> setup, then ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> same, extra args to `ephpm serve`
#   entrypoint.sh <command...>    -> wait for APP_KEY + the DB, then run <command>
#                                    (the scheduler sidecar; `docker compose run --rm ephpm ephpm php artisan ...`)
set -eu
cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
case "${1:-}" in ""|-*) SERVE=1 ;; *) SERVE=0 ;; esac

# storage/ is a volume: seed the directory layout when it starts out empty.
[ -d storage/framework ] || cp -a /usr/local/share/filament-demo/storage/. storage/
mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs storage/app/public

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

case "${DB_CONNECTION:-sqlite}" in
    sqlite)
        # Laravel's default SQLite path is database/database.sqlite (in the
        # image); the compose file points DB_DATABASE into the storage volume.
        db="${DB_DATABASE:-/app/database/database.sqlite}"
        mkdir -p "$(dirname "$db")"; [ -e "$db" ] || touch "$db"
        ;;
    *)
        echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-5432}"
        i=0
        until ephpm php -r '
            try { new PDO(sprintf("%s:host=%s;port=%s;dbname=%s", getenv("DB_CONNECTION") === "pgsql" ? "pgsql" : "mysql", getenv("DB_HOST") ?: "db", getenv("DB_PORT") ?: "5432", getenv("DB_DATABASE")), getenv("DB_USERNAME"), getenv("DB_PASSWORD")); exit(0); }
            catch (Throwable $e) { exit(1); }
        ' 2>/dev/null; do
            i=$((i + 1))
            [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
            sleep 2
        done
        ;;
esac

[ "$SERVE" = 1 ] || exec "$@"

echo "==> migrating"
ephpm php artisan migrate --force --no-interaction

# The demo data (admin user, shop, blog, HR records) once, on an empty database.
users="$(ephpm php -r '
    require "vendor/autoload.php";
    $app = require "bootstrap/app.php";
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    echo App\Models\User::count();
' 2>/dev/null | tail -n 1 || echo 0)"
if [ "$users" = "0" ] && [ "${DEMO_SEED:-1}" = "1" ]; then
    echo "==> seeding the demo data (takes a minute)"
    ephpm php artisan db:seed --force --no-interaction
fi

ephpm php artisan optimize >/dev/null

exec ephpm serve --config "$CONFIG" "$@"
