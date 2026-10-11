#!/bin/sh
# Container entrypoint: first-run setup, migrations, then ePHPm in the
# foreground.
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
for d in app/public framework/cache framework/sessions framework/views fonts logs uploads/files uploads/images; do
    mkdir -p "$STORAGE/$d"
done
[ -e "$APP/public/uploads/.gitignore" ] || cp -a /usr/local/share/bookstack/uploads/. "$APP/public/uploads/"
[ -e "$APP/themes" ] || cp -a /usr/local/share/bookstack/themes "$APP/themes"

# .env lives in the storage volume and /app/.env points at it, so the APP_KEY
# generated below survives container recreation. Everything else comes from
# the container environment, which Laravel never overrides from .env.
if [ ! -f "$STORAGE/.env" ]; then
    cp "$APP/.env.example" "$STORAGE/.env"
fi
ln -sfn "$STORAGE/.env" "$APP/.env"

if grep -q '^APP_KEY=SomeRandomString' "$STORAGE/.env" && [ -z "${APP_KEY:-}" ]; then
    key="base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')"
    sed -i "s|^APP_KEY=.*|APP_KEY=$key|" "$STORAGE/.env"
    echo "==> generated APP_KEY into storage/.env"
fi

# Wait for the database.
echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
i=0
until ephpm php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "bookstack", (int) (getenv("DB_PORT") ?: 3306));
    exit($c ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at ${DB_HOST:-db} not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*)
        # Sets up a fresh database (and seeds the admin@admin.com account) or
        # migrates an existing one — the same step the official image runs.
        echo "==> running database migrations"
        ephpm php artisan migrate --force --no-interaction
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
