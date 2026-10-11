#!/bin/sh
# Container entrypoint: the official build/scripts/entrypoint.sh's steps on
# the embedded PHP — migrate (unless DATABASE_DISABLE_AUTO_MIGRATION),
# storage:link, optionally create the first admin — then ePHPm in the
# foreground. With arguments (the `jobs` service: `movary jobs:process`) it
# skips the setup and runs them instead.
set -eu

cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# storage/ (SQLite file, logs, image cache, app data) lives in a volume;
# seed it when it was created empty.
[ -n "$(ls -A storage 2>/dev/null)" ] || cp -a /usr/local/share/movary-storage/. storage/
mkdir -p storage/app storage/logs

# APPLICATION_SECRET is required and must be stable: the environment wins,
# otherwise generate one once into the storage volume.
if [ -z "${APPLICATION_SECRET:-}" ]; then
    [ -s storage/.application-secret ] || ( umask 077 && ephpm php -r 'echo bin2hex(random_bytes(32));' > storage/.application-secret )
    APPLICATION_SECRET="$(cat storage/.application-secret)"
    export APPLICATION_SECRET
fi

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

DB_MODE="${DATABASE_MODE:-sqlite}"
DB_HOST="${DATABASE_MYSQL_HOST:-}"
DB_PORT="${DATABASE_MYSQL_PORT:-3306}"

wait_db() {
    echo "==> waiting for database at $DB_HOST:$DB_PORT"
    i=0
    until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$DB_HOST" "$DB_PORT" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 90 ] && { echo "!!! database at $DB_HOST:$DB_PORT not reachable after 90 tries" >&2; exit 1; }
        sleep 2
    done
}

setup() {
    case "${DATABASE_DISABLE_AUTO_MIGRATION:-0}" in
        true|1) echo "==> automatic database migration is disabled" ;;
        *)      movary database:migration:migrate ;;
    esac
    movary storage:link
    # Optional first admin (idempotent: skipped once the e-mail exists).
    if [ -n "${ADMIN_EMAIL:-}" ] && [ -n "${ADMIN_PASSWORD:-}" ]; then
        if movary user:list 2>/dev/null | grep -F "$ADMIN_EMAIL" >/dev/null; then
            echo "==> admin user $ADMIN_EMAIL already exists"
        else
            movary user:create "$ADMIN_EMAIL" "$ADMIN_PASSWORD" "${ADMIN_NAME:-admin}" 1
            echo "==> admin user $ADMIN_EMAIL created"
        fi
    fi
    echo "==> Movary is ready"
}

case "$DB_MODE:$DB_HOST" in
    sqlite:*)                 setup ;;
    *:127.0.0.1|*:localhost)  ( wait_db; setup ) & ;;    # embedded listener starts with the server
    *)                        wait_db; setup ;;
esac

exec ephpm serve --config "$CONFIG"
