#!/bin/sh
# Container entrypoint: wait for the database, run SolidInvoice's own
# installer once (`app:install` — schema, the admin user, the application
# URL; it writes the result into the SOLIDINVOICE_CONFIG_DIR vault), then
# ePHPm in the foreground.
set -eu

cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
mkdir -p "$SOLIDINVOICE_CONFIG_DIR/db" var/cache var/log

DB_DRIVER="${DATABASE_DRIVER:-pdo_mysql}"
DB_HOST="${DATABASE_HOST:-db}"
DB_PORT="${DATABASE_PORT:-3306}"
DB_NAME="${DATABASE_NAME:-solidinvoice}"
DB_USER="${DATABASE_USER:-solidinvoice}"
DB_PASSWORD="${DATABASE_PASSWORD:-solidinvoice}"

# Until `app:install` has sealed the database URL into the vault, the kernel
# would boot against its default SQLite URL; hand it the real one.
case "$DB_DRIVER" in
    pdo_mysql|mysql)  export SOLIDINVOICE_DATABASE_URL="${SOLIDINVOICE_DATABASE_URL:-mysql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME?serverVersion=11.4.0-MariaDB&charset=utf8mb4}" ;;
    pdo_pgsql|postgres*) export SOLIDINVOICE_DATABASE_URL="${SOLIDINVOICE_DATABASE_URL:-postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME?serverVersion=17}" ;;
esac

echo "==> waiting for database at $DB_HOST:$DB_PORT"
i=0
until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$DB_HOST" "$DB_PORT" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 90 ] && { echo "!!! database at $DB_HOST:$DB_PORT not reachable after 90 tries" >&2; exit 1; }
    sleep 2
done

rm -rf var/cache/*
if solidinvoice solidinvoice:is-installed >/dev/null 2>&1; then
    echo "==> already installed; running migrations"
    solidinvoice doctrine:migrations:migrate --no-interaction --allow-no-migration
else
    if [ -z "${ADMIN_EMAIL:-}" ] || [ -z "${ADMIN_PASSWORD:-}" ]; then
        echo "==> not installed and ADMIN_EMAIL/ADMIN_PASSWORD unset: open the web installer at ${APPLICATION_URL:-http://localhost:8080}/install"
    else
        echo "==> installing (schema + admin user)"
        install() {
            solidinvoice app:install --no-interaction "$@" \
                --database-driver="$DB_DRIVER" --database-host="$DB_HOST" --database-port="$DB_PORT" \
                --database-name="$DB_NAME" --database-user="$DB_USER" --database-password="$DB_PASSWORD" \
                --admin-email="$ADMIN_EMAIL" --admin-password="$ADMIN_PASSWORD" \
                --locale="${LOCALE:-en}" --application-url="${APPLICATION_URL:-http://localhost:8080}" \
                ${DISABLE_TELEMETRY:+--disable-telemetry}
        }
        # SolidInvoice 3.0.1's `app:install` never iterates its generator-based
        # installation steps, so "Creating database schema" is a no-op on the
        # CLI (the web installer consumes the same steps through its event
        # stream) and the admin-user step fails on the missing `users` table —
        # UPSTREAM.md (SolidInvoice). So: run it once to seed the vault (secret,
        # build id, database settings), build the schema the way the web
        # installer does (SchemaTool, then mark every migration executed), and
        # run it again for the admin user and the "installed" marker.
        # (schema:update rather than schema:create so a start that died
        # half-way through can be retried)
        install --skip-user >/dev/null 2>&1 || true
        solidinvoice doctrine:schema:update --force --complete --no-interaction >/dev/null
        solidinvoice doctrine:migrations:sync-metadata-storage --no-interaction >/dev/null
        solidinvoice doctrine:migrations:version --add --all --no-interaction >/dev/null
        install
    fi
fi
solidinvoice cache:warmup --no-interaction >/dev/null
echo "==> SolidInvoice is ready"

exec ephpm serve --config "$CONFIG"
