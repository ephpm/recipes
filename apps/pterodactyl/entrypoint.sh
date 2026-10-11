#!/bin/sh
# Container entrypoint: the official image's .github/docker/entrypoint.sh
# without nginx/certbot/crond/supervisord — .env with APP_KEY and
# HASHIDS_SALT in the /app/var volume, wait for the database, migrate and
# seed, plus the first admin user (`p:user:make`), then ePHPm.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> once the server has set up
#                                    (the queue and scheduler services)
set -eu

APP=/app
VAR=/app/var
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

mkdir -p "$APP/storage/logs" "$APP/storage/framework/cache" "$APP/storage/framework/sessions" \
    "$APP/storage/framework/views" "$APP/bootstrap/cache"

case "${1:-}" in
    ""|-*)
        # .env in the volume, generated once (as the official entrypoint does).
        if [ ! -f "$VAR/.env" ]; then
            key="${APP_KEY:-base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')}"
            salt="${HASHIDS_SALT:-$(ephpm php -r 'echo bin2hex(random_bytes(10));')}"
            printf 'APP_KEY=%s\nHASHIDS_SALT=%s\n' "$key" "$salt" > "$VAR/.env"
            echo "==> generated APP_KEY and HASHIDS_SALT into /app/var/.env"
        fi
        ;;
    *)
        # Sidecars share the volume: wait until the server has migrated.
        i=0
        until [ -f "$VAR/.ephpm-installed" ]; do
            i=$((i + 1)); [ "$i" -ge 300 ] && { echo "!!! the panel did not finish setting up after 300s" >&2; exit 1; }
            sleep 1
        done
        ;;
esac

echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
i=0
until ephpm php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "pterodactyl", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "panel", (int) (getenv("DB_PORT") ?: 3306));
    exit($c ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*)
        echo "==> migrating and seeding the database"
        ephpm php artisan migrate --seed --force --no-interaction
        if [ ! -f "$VAR/.ephpm-installed" ]; then
            # The first administrator (the official image leaves this to
            # `php artisan p:user:make` by hand).
            echo "==> creating the admin user (${PTERODACTYL_ADMIN_EMAIL:-admin@example.com})"
            ephpm php artisan p:user:make --admin=1 --no-interaction \
                --email="${PTERODACTYL_ADMIN_EMAIL:-admin@example.com}" \
                --username="${PTERODACTYL_ADMIN_USERNAME:-admin}" \
                --name-first="${PTERODACTYL_ADMIN_FIRST_NAME:-Panel}" \
                --name-last="${PTERODACTYL_ADMIN_LAST_NAME:-Admin}" \
                --password="${PTERODACTYL_ADMIN_PASSWORD:-changeme}"
            touch "$VAR/.ephpm-installed"
        fi
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
