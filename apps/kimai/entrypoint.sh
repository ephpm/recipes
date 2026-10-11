#!/bin/sh
# Container entrypoint: the official kimai/kimai2 entrypoint's steps on the
# embedded PHP — resolve APP_SECRET, wait for the database, `kimai:install`
# (create DB, migrations, cache), optionally create the admin — then ePHPm
# in the foreground.
set -eu

cd /opt/kimai
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# var/ lives in a volume; seed it when it was created empty.
if [ -z "$(ls -A var 2>/dev/null)" ]; then
    cp -a /usr/local/share/kimai-var/. var/
fi
mkdir -p var/cache var/data var/log var/plugins var/sessions

# APP_SECRET: the environment wins; otherwise generate one once and keep it in
# the var/data volume, mirrored into .env.local for `docker compose exec`
# console runs (the same scheme as the official image).
rm -f .env.local
if [ -z "${APP_SECRET:-}" ] || [ "$APP_SECRET" = "change_this_to_something_unique" ]; then
    if [ ! -s var/data/.appsecret ]; then
        ( umask 077 && ephpm php -r 'echo bin2hex(random_bytes(32));' > var/data/.appsecret )
        echo "==> APP_SECRET: generated and persisted to var/data/.appsecret"
    fi
    APP_SECRET="$(cat var/data/.appsecret)"
    export APP_SECRET
    printf 'APP_SECRET=%s\n' "$APP_SECRET" > .env.local
fi

export DATABASE_URL="${DATABASE_URL:-mysql://kimai:kimai@127.0.0.1:3306/kimai?charset=utf8mb4&serverVersion=11.4.0-MariaDB}"
export APP_ENV="${APP_ENV:-prod}"

# Wait for the database host (the embedded one starts with the server).
DB_HOST="$(ephpm php -r 'echo parse_url($argv[1], PHP_URL_HOST) ?: "127.0.0.1";' "$DATABASE_URL")"
DB_PORT="$(ephpm php -r 'echo parse_url($argv[1], PHP_URL_PORT) ?: 3306;' "$DATABASE_URL")"

wait_db() {
    echo "==> waiting for database at $DB_HOST:$DB_PORT"
    i=0
    until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$DB_HOST" "$DB_PORT" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 90 ] && { echo "!!! database at $DB_HOST:$DB_PORT not reachable after 90 tries" >&2; exit 1; }
        sleep 2
    done
}

install() {
    # Idempotent: creates the database if missing, runs migrations, warms the cache.
    kimai kimai:install --no-interaction
    if [ -n "${ADMINPASS:-}" ] && [ -n "${ADMINMAIL:-}" ]; then
        # --ignore-existing: only the first start creates the admin
        kimai kimai:user:create --ignore-existing admin "$ADMINMAIL" ROLE_SUPER_ADMIN "$ADMINPASS"
    fi
    cat version.txt > var/installed
    echo "==> Kimai is ready"
}

case "$DB_HOST" in
    127.0.0.1|localhost)
        ( wait_db; install ) &
        ;;
    *)
        wait_db
        install
        ;;
esac

exec ephpm serve --config "$CONFIG" "$@"
