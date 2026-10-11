#!/bin/sh
# First-run setup, then ePHPm in the foreground.
set -eu
cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
mkdir -p var/cache var/log data

# Wait for an external MySQL/PostgreSQL named in DATABASE_URL.
host="$(printf '%s' "${DATABASE_URL:-}" | sed -nE 's#^[a-z]+://([^@]*@)?([^:/?]+).*#\2#p')"
case "${DATABASE_URL:-}" in
    sqlite*) ;;
    *)
        case "$host" in
            127.0.0.1|localhost|"") ;;
            *)
                echo "==> waiting for database at $host"
                i=0
                until ephpm php bin/console dbal:run-sql 'SELECT 1' >/dev/null 2>&1; do
                    i=$((i + 1))
                    [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
                    sleep 2
                done
                ;;
        esac
        ;;
esac

setup_schema() {
    # Create the schema and load the demo fixtures once.
    if ! ephpm php bin/console dbal:run-sql 'SELECT COUNT(*) FROM symfony_demo_user' >/dev/null 2>&1; then
        echo "==> creating schema + loading fixtures"
        ephpm php bin/console doctrine:schema:create --no-interaction
        # the fixtures bundle is only registered in the dev environment
        ephpm php bin/console doctrine:fixtures:load --env=dev --no-interaction
        rm -rf var/cache/dev
    fi
}

case "${DATABASE_URL:-}" in
    *127.0.0.1*|*localhost*)
        # Embedded database: only reachable once the server is up.
        ( i=0
          until ephpm php bin/console dbal:run-sql 'SELECT 1' >/dev/null 2>&1; do
              i=$((i + 1)); [ "$i" -ge 60 ] && exit 1; sleep 1
          done
          setup_schema ) &
        ;;
    *) setup_schema ;;
esac

ephpm php bin/console cache:warmup >/dev/null
exec ephpm serve --config "$CONFIG" "$@"
