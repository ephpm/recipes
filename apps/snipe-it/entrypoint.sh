#!/bin/sh
# Container entrypoint: first-run setup, migrations, then ePHPm in the
# foreground. Mirrors the official image's startup script.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
#                                    (`docker compose run --rm ephpm ephpm php artisan ...`)
set -eu

APP=/app
STORAGE=$APP/storage
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# storage/ and public/uploads are volumes. Seed what the image ships when a
# volume started out empty (a bind mount, or a pre-created one).
for d in app/backups app/public framework/cache framework/sessions framework/views logs; do
    mkdir -p "$STORAGE/$d"
done
[ -e "$STORAGE/private_uploads/assets" ] || cp -an /usr/local/share/snipe-it/storage/private_uploads "$STORAGE/"
[ -e "$APP/public/uploads/default.png" ] || cp -an /usr/local/share/snipe-it/uploads/. "$APP/public/uploads/"

# .env lives in the storage volume and /app/.env points at it, so the APP_KEY
# generated below survives container recreation. Everything else comes from
# the container environment, which Laravel never overrides from .env.
# Only the server seeds it; a command container (the scheduler) waits for
# the seed so the two never race on the same file.
case "${1:-}" in
    ""|-*)
        if [ ! -f "$STORAGE/.env" ]; then
            cp /usr/local/share/snipe-it/env.template "$STORAGE/.env"
        fi
        if grep -q '^APP_KEY=ChangeMe' "$STORAGE/.env" && [ -z "${APP_KEY:-}" ]; then
            key="base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')"
            sed -i "s|^APP_KEY=.*|APP_KEY=$key|" "$STORAGE/.env"
            echo "==> generated APP_KEY into storage/.env"
        fi
        ;;
    *)
        i=0
        until [ -f "$STORAGE/.env" ] && ! grep -q '^APP_KEY=ChangeMe' "$STORAGE/.env"; do
            i=$((i + 1)); [ "$i" -ge 120 ] && { echo "!!! storage/.env was not seeded by the server after 120s" >&2; exit 1; }
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
    $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "snipeit", (int) (getenv("DB_PORT") ?: 3306));
    exit($c ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at ${DB_HOST:-db} not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*)
        # Same as the official startup script: migrate (a fresh database gets
        # the schema; the web setup then creates the admin), clear the
        # config cache so .env/environment changes apply.
        echo "==> running database migrations"
        ephpm php artisan migrate --force --no-interaction
        ephpm php artisan config:clear >/dev/null
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
