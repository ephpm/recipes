#!/bin/sh
# Container entrypoint: first-run setup, then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
#                                    (used by the scheduler service and
#                                    `docker compose run ephpm ephpm php artisan ...`)
set -eu

APP=/app
STORAGE=$APP/storage
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# storage/ is a volume. Seed the directories Laravel needs when the volume
# started out empty (a bind mount, or a pre-created one).
for d in app/backups app/backup-temp app/public app/temp framework/cache framework/sessions framework/views logs; do
    mkdir -p "$STORAGE/$d"
done

# .env lives in the storage volume and /app/.env points at it: the APP_KEY
# generated below and the database settings the setup wizard writes must
# survive container recreation (the official image bind-mounts ./.env).
# Only the server seeds it; a command container (the scheduler) waits for
# the seed so the two never race on the same file.
case "${1:-}" in
    ""|-*)
        if [ ! -f "$STORAGE/.env" ]; then
            cp /usr/local/share/linkace/env.template "$STORAGE/.env"
        fi
        # Generate the application key once (LinkAce would otherwise do it on
        # the first request and log a warning about the insecure placeholder).
        if grep -q '^APP_KEY=someRandomStringWith32Characters' "$STORAGE/.env" && [ -z "${APP_KEY:-}" ]; then
            key="base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')"
            sed -i "s|^APP_KEY=.*|APP_KEY=$key|" "$STORAGE/.env"
            echo "==> generated APP_KEY into storage/.env"
        fi
        ;;
    *)
        i=0
        until [ -f "$STORAGE/.env" ] && ! grep -q '^APP_KEY=someRandomStringWith32Characters' "$STORAGE/.env"; do
            i=$((i + 1)); [ "$i" -ge 120 ] && { echo "!!! storage/.env was not seeded by the server after 120s" >&2; exit 1; }
            sleep 1
        done
        ;;
esac
ln -sfn "$STORAGE/.env" "$APP/.env"

# Wait for an external database (the embedded one starts with the server).
DB_HOST="${DB_HOST:-127.0.0.1}"
case "$DB_HOST" in
    127.0.0.1|localhost) ;;
    *)
        echo "==> waiting for database at $DB_HOST:${DB_PORT:-3306}"
        i=0
        until ephpm php -r '
            mysqli_report(MYSQLI_REPORT_OFF);
            $c = @mysqli_connect(getenv("DB_HOST"), getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "linkace", (int) (getenv("DB_PORT") ?: 3306));
            exit($c ? 0 : 1);
        ' 2>/dev/null; do
            i=$((i + 1))
            [ "$i" -ge 60 ] && { echo "!!! database at $DB_HOST not reachable after 60 tries" >&2; exit 1; }
            sleep 2
        done
        ;;
esac

case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *)     exec "$@" ;;
esac
