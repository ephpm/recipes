#!/bin/sh
# Container entrypoint: first-run setup, database upgrade, then ePHPm in the
# foreground. Mirrors the official image's entrypoint.sh (same artisan
# commands, same order).
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
#                                    (`docker compose run --rm ephpm ephpm php artisan ...`)
set -eu

APP=/app
STORAGE=$APP/storage
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# storage/ is a volume. Seed the directories Firefly III needs (the list the
# official image's finalize-image.sh creates) when the volume started empty.
for d in app/public build database debugbar export framework/cache/data framework/sessions framework/testing framework/views/twig framework/views/v1 framework/views/v2 logs upload; do
    mkdir -p "$STORAGE/$d"
done

# .env lives in the storage volume and /app/.env points at it, so the APP_KEY
# generated below survives container recreation. Everything else comes from
# the container environment, which Laravel never overrides from .env.
if [ ! -f "$STORAGE/.env" ]; then
    cp "$APP/.env.example" "$STORAGE/.env"
fi
ln -sfn "$STORAGE/.env" "$APP/.env"

if grep -q '^APP_KEY=SomeRandomStringOf32CharsExactly' "$STORAGE/.env" && [ -z "${APP_KEY:-}" ]; then
    # Firefly III wants a plain 32-character key (see .env.example).
    key="$(ephpm php -r 'echo substr(bin2hex(random_bytes(16)), 0, 32);')"
    sed -i "s|^APP_KEY=.*|APP_KEY=$key|" "$STORAGE/.env"
    echo "==> generated APP_KEY into storage/.env"
fi

# Wait for the database.
echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
i=0
until ephpm php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "firefly", (int) (getenv("DB_PORT") ?: 3306));
    exit($c ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at ${DB_HOST:-db} not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*)
        # The official entrypoint's sequence: create/upgrade the schema,
        # make sure the Passport keys exist, record the version.
        echo "==> upgrading the database"
        ephpm php artisan firefly-iii:create-database
        ephpm php artisan firefly-iii:upgrade-database
        ephpm php artisan firefly-iii:laravel-passport-keys
        chmod 600 "$STORAGE/oauth-public.key" "$STORAGE/oauth-private.key"
        ephpm php artisan firefly-iii:set-latest-version --james-is-cool
        ephpm php artisan event:clear >/dev/null 2>&1 || true
        ephpm php artisan cache:clear >/dev/null 2>&1 || true
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
