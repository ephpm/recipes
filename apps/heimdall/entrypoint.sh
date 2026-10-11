#!/bin/sh
# Container entrypoint: seed the volumes, create .env with an APP_KEY, then
# ePHPm in the foreground. Heimdall creates and migrates its SQLite database
# itself (AppServiceProvider::setupDatabase) on the first request; the
# entrypoint runs the same migration up front so the first page is fast.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

APP=/app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$APP"

# storage/ is a volume: seed what the image ships (supportedapps.json etc.).
[ -e "$APP/storage/app/supportedapps.json" ] || cp -a /usr/local/share/heimdall/storage/. "$APP/storage/"
for d in app/public/icons framework/cache/data framework/sessions framework/views logs; do
    mkdir -p "$APP/storage/$d"
done

# .env lives in the data volume (/app/.env points at it), as in the
# linuxserver image's /config; settings in the container environment win.
if [ ! -f /data/.env ]; then
    cp "$APP/.env.example" /data/.env
    key="base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')"
    sed -i "s|^APP_KEY=.*|APP_KEY=$key|" /data/.env
    echo "==> created /data/.env with a generated APP_KEY"
fi
[ -f /data/app.sqlite ] || touch /data/app.sqlite

echo "==> running database migrations"
ephpm php artisan migrate --path=database/migrations --force --seed --no-interaction

case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
