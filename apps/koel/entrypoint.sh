#!/bin/sh
# Container entrypoint: first-run setup (koel:init), then ePHPm in the
# foreground.
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

# storage/ is a volume. Seed the directories Koel needs when the volume
# started out empty (a bind mount, or a pre-created one).
for d in app/public/images framework/cache framework/sessions framework/views logs search-indexes; do
    mkdir -p "$STORAGE/$d"
done

# .env lives in the storage volume and /app/.env points at it: koel:init
# writes the APP_KEY it generates there, and the official image likewise
# keeps .env outside the image. Values set in the container environment win
# over the file.
# Only the server seeds it; a command container (the scheduler) waits for
# the seed (koel:init writes APP_KEY into it) so the two never race.
case "${1:-}" in
    ""|-*)
        if [ ! -f "$STORAGE/.env" ]; then
            cp "$APP/.env.example" "$STORAGE/.env"
            sed -i 's|^APP_DEBUG=.*|APP_DEBUG=false|; s|^MEDIA_PATH=.*|MEDIA_PATH=/music|' "$STORAGE/.env"
        fi
        ;;
    *)
        i=0
        until [ -f "$STORAGE/.env" ] && grep -q '^APP_KEY=.\+' "$STORAGE/.env"; do
            i=$((i + 1)); [ "$i" -ge 180 ] && { echo "!!! storage/.env was not seeded by the server after 180s" >&2; exit 1; }
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
    $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "koel", (int) (getenv("DB_PORT") ?: 3306));
    exit($c ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at ${DB_HOST:-db} not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*)
        # What the official image runs on every start: generates APP_KEY on
        # the first run, migrates, creates the admin@koel.dev account and
        # links storage. --no-scheduler: there is no crontab here, the
        # scheduler service runs `artisan schedule:run` instead.
        echo "==> running koel:init"
        ephpm php artisan koel:init --no-assets --no-interaction --no-scheduler
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
