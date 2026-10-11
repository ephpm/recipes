#!/bin/sh
# Container entrypoint: first-run setup (migrations + the first account),
# then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
#                                    (used by the scheduler service and
#                                    `docker compose run --rm ephpm ephpm php artisan ...`)
set -eu

APP=/app
STORAGE=$APP/storage
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# storage/ and public/storage are volumes. Seed what Laravel needs when a
# volume started out empty (a bind mount, or a pre-created one).
for d in app/public framework/cache framework/sessions framework/views logs; do
    mkdir -p "$STORAGE/$d"
done
mkdir -p "$APP/public/storage"

# .env lives in the storage volume and /app/.env points at it, so the APP_KEY
# generated below survives container recreation. Everything else comes from
# the container environment, which Laravel never overrides from .env. Only
# the server seeds it; a command container (the scheduler) waits for the seed.
case "${1:-}" in
    ""|-*)
        if [ ! -f "$STORAGE/.env" ]; then
            # the example file carries a well-known placeholder key: replace it
            cp "$APP/.env.example" "$STORAGE/.env"
            key="base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')"
            sed -i "s|^APP_KEY=.*|APP_KEY=$key|" "$STORAGE/.env"
            echo "==> generated APP_KEY into storage/.env"
        fi
        ;;
    *)
        i=0
        until [ -f "$STORAGE/.ephpm-installed" ]; do
            i=$((i + 1)); [ "$i" -ge 240 ] && { echo "!!! the server did not finish installing after 240s" >&2; exit 1; }
            sleep 1
        done
        ;;
esac
ln -sfn "$STORAGE/.env" "$APP/.env"

# Wait for the database.
echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
i=0
until ephpm php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "ninja", (int) (getenv("DB_PORT") ?: 3306));
    exit($c ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at ${DB_HOST:-db} not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*)
        echo "==> running database migrations"
        ephpm php artisan migrate --force --no-interaction
        if [ ! -f "$STORAGE/.ephpm-installed" ]; then
            # Reference data (currencies, countries, payment types, …): the
            # upstream install is `migrate` + `db:seed`.
            echo "==> seeding reference data"
            ephpm php artisan db:seed --force --no-interaction
            # The first account/company/user, what the web signup would create.
            echo "==> creating the first account (${NINJA_ADMIN_EMAIL:-admin@example.com})"
            ephpm php artisan ninja:create-account \
                --email="${NINJA_ADMIN_EMAIL:-admin@example.com}" \
                --password="${NINJA_ADMIN_PASSWORD:-changeme!}"
            touch "$STORAGE/.ephpm-installed"
        fi
        ephpm php artisan optimize:clear >/dev/null 2>&1 || true
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
