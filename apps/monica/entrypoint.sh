#!/bin/sh
# Container entrypoint: first-run setup, database update, then ePHPm in the
# foreground. Mirrors the official image's entrypoint.sh.
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

# storage/ is a volume. Seed the directories Monica needs (the official
# entrypoint creates the same ones) when the volume started out empty.
for d in app/public framework/cache framework/sessions framework/views logs; do
    mkdir -p "$STORAGE/$d"
done

# .env lives in the storage volume and /app/.env points at it, so the keys
# generated below survive container recreation. Everything else comes from
# the container environment, which Laravel never overrides from .env.
# Only the server seeds it; a command container (the scheduler) waits for
# the seed so the two never race on the same file.
case "${1:-}" in
    ""|-*)
        if [ ! -f "$STORAGE/.env" ]; then
            cp "$APP/.env.example" "$STORAGE/.env"
        fi
        if grep -q '^APP_KEY=ChangeMeBy32KeyLengthOrGenerated' "$STORAGE/.env" && [ -z "${APP_KEY:-}" ]; then
            key="base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')"
            sed -i "s|^APP_KEY=.*|APP_KEY=$key|" "$STORAGE/.env"
            echo "==> generated APP_KEY into storage/.env"
        fi
        if grep -q '^HASH_SALT=ChangeMeBy20+KeyLength' "$STORAGE/.env" && [ -z "${HASH_SALT:-}" ]; then
            salt="$(ephpm php -r 'echo bin2hex(random_bytes(16));')"
            sed -i "s|^HASH_SALT=.*|HASH_SALT=$salt|" "$STORAGE/.env"
            echo "==> generated HASH_SALT into storage/.env"
        fi
        ;;
    *)
        i=0
        until [ -f "$STORAGE/.env" ] && ! grep -q '^APP_KEY=ChangeMeBy32KeyLengthOrGenerated' "$STORAGE/.env"; do
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
    $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "monica", (int) (getenv("DB_PORT") ?: 3306));
    exit($c ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at ${DB_HOST:-db} not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*)
        # The official entrypoint's sequence: migrate/update, then make
        # sure the Passport keys and the personal-access client exist.
        # (`monica:update` reported "Performing migrations" on an empty
        # database without creating a single table, so migrate explicitly
        # first — idempotent on an existing database.)
        echo "==> running migrations and monica:update"
        ephpm php artisan migrate --force --no-interaction
        ephpm php artisan monica:update --force
        if [ ! -f "$STORAGE/oauth-public.key" ] || [ ! -f "$STORAGE/oauth-private.key" ]; then
            echo "==> creating Passport keys"
            ephpm php artisan passport:keys
            ephpm php artisan passport:client --personal --no-interaction
        fi
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
