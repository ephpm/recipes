#!/bin/sh
# Container entrypoint: APP_KEY, migrations and (once) the first admin user,
# then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> once the server has
#                                    migrated (the scheduler and queue
#                                    services, `docker compose run --rm ...`)
set -eu

APP=/app
STORAGE=$APP/storage
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# storage/ is a volume. Seed it when it started out empty.
[ -d "$STORAGE/framework" ] || cp -a /usr/local/share/cachet/storage/. "$STORAGE/"
for d in app/public framework/cache/data framework/sessions framework/views logs; do
    mkdir -p "$STORAGE/$d"
done

# .env lives in the storage volume (APP_KEY must survive container
# recreation); everything else comes from the container environment, which
# Laravel never overrides from .env.
case "${1:-}" in
    ""|-*) [ -f "$STORAGE/.env" ] || cp "$APP/.env.example" "$STORAGE/.env" ;;
    *)
        i=0
        until [ -f "$STORAGE/.migrated" ]; do
            i=$((i + 1)); [ "$i" -ge 600 ] && { echo "!!! the server did not migrate the database after 600s" >&2; exit 1; }
            sleep 1
        done
        ;;
esac
ln -sfn "$STORAGE/.env" "$APP/.env"

if [ -z "${APP_KEY:-}" ] && grep -q '^APP_KEY=$' "$STORAGE/.env"; then
    key="base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')"
    sed -i "s|^APP_KEY=.*|APP_KEY=$key|" "$STORAGE/.env"
    echo "==> generated APP_KEY into storage/.env"
fi

DB_CONNECTION="${DB_CONNECTION:-sqlite}"
if [ "$DB_CONNECTION" = "sqlite" ]; then
    # Cachet's native SQLite file (DB_DATABASE, default storage/database.sqlite)
    DB_DATABASE="${DB_DATABASE:-$STORAGE/database.sqlite}"
    export DB_DATABASE
    [ -f "$DB_DATABASE" ] || { mkdir -p "$(dirname "$DB_DATABASE")"; touch "$DB_DATABASE"; }
else
    echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
    i=0
    until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "${DB_HOST:-db}" "${DB_PORT:-3306}" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 90 ] && { echo "!!! database at ${DB_HOST:-db} not reachable after 90 tries" >&2; exit 1; }
        sleep 2
    done
fi

case "${1:-}" in
    ""|-*) ;;
    *) exec "$@" ;;
esac

echo "==> running database migrations"
ephpm php artisan migrate --force --no-interaction
touch "$STORAGE/.migrated"

# First admin (Cachet's own `cachet:make:user`), once.
if [ ! -f "$STORAGE/.admin-created" ] && [ -n "${CACHET_ADMIN_EMAIL:-}" ] && [ -n "${CACHET_ADMIN_PASSWORD:-}" ]; then
    echo "==> creating the admin user $CACHET_ADMIN_EMAIL"
    ephpm php artisan cachet:make:user "$CACHET_ADMIN_EMAIL" \
        --password="$CACHET_ADMIN_PASSWORD" --name="${CACHET_ADMIN_NAME:-Admin}" --admin=1 --no-interaction
    touch "$STORAGE/.admin-created"
fi
echo "==> Cachet is ready"
exec ephpm serve --config "$CONFIG" "$@"
