#!/bin/sh
# Container entrypoint: seed the volumes and .env, generate APP_KEY once,
# wait for the database, migrate, create the admin on the first start, then
# ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

APP=/app
SEED=/usr/local/share/lychee
cd "$APP"

[ -n "$(ls -A storage 2>/dev/null)" ] || cp -a "$SEED/storage/." storage/
[ -n "$(ls -A public/uploads 2>/dev/null)" ] || cp -a "$SEED/uploads/." public/uploads/
for d in app framework/cache/data framework/sessions framework/views logs; do mkdir -p "storage/$d"; done

# .env lives in the storage volume (APP_KEY must survive re-creation); all
# other settings come from the container environment, which wins over it.
[ -f storage/.env ] || cp .env.example storage/.env
ln -sfn storage/.env .env
if grep -q '^APP_KEY=$' storage/.env && [ -z "${APP_KEY:-}" ]; then
    key="base64:$(php -r 'echo base64_encode(random_bytes(32));')"
    sed -i "s|^APP_KEY=.*|APP_KEY=$key|" storage/.env
    echo "==> generated APP_KEY into storage/.env"
fi

if [ "${DB_CONNECTION:-sqlite}" != "sqlite" ]; then
    echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
    i=0
    until php -r '
        try { new PDO(sprintf("%s:host=%s;port=%s;dbname=%s", getenv("DB_CONNECTION") === "pgsql" ? "pgsql" : "mysql",
              getenv("DB_HOST") ?: "db", getenv("DB_PORT") ?: "3306", getenv("DB_DATABASE") ?: "lychee"),
              getenv("DB_USERNAME") ?: "lychee", getenv("DB_PASSWORD") ?: ""); exit(0); } catch (Throwable $e) { exit(1); }
    ' 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
        sleep 2
    done
fi

echo "==> running database migrations"
php artisan migrate --force --no-interaction

# First start: create the administrator from LYCHEE_ADMIN_USER/_PASSWORD
# (otherwise Lychee asks for one in the browser).
if [ -n "${LYCHEE_ADMIN_PASSWORD:-}" ] && [ ! -f storage/.ephpm-admin-created ]; then
    php artisan lychee:create_user "${LYCHEE_ADMIN_USER:-admin}" "$LYCHEE_ADMIN_PASSWORD" \
        --may-administrate --may-upload --may-edit-own-settings \
        && touch storage/.ephpm-admin-created
fi

case "${1:-}" in
    ""|-*) exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@" ;;
    *) exec "$@" ;;
esac
