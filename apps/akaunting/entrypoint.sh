#!/bin/sh
# Container entrypoint: first-run installation (Akaunting's own `artisan
# install`), then ePHPm in the foreground.
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

# storage/ is a volume. Seed the directories Laravel needs when the volume
# started out empty (a bind mount, or a pre-created one).
for d in app/public framework/cache framework/sessions framework/views logs; do
    mkdir -p "$STORAGE/$d"
done

# .env lives in the storage volume and /app/.env points at it: `artisan
# install` writes APP_KEY, APP_INSTALLED and the database settings into it,
# and they must survive container recreation. Values set in the container
# environment still win over the file. Only the server seeds it; a command
# container (the scheduler) waits for the installation to finish.
case "${1:-}" in
    ""|-*)
        [ -f "$STORAGE/.env" ] || cp "$APP/.env.example" "$STORAGE/.env"
        ;;
    *)
        i=0
        until [ -f "$STORAGE/.env" ] && grep -q '^APP_INSTALLED=true' "$STORAGE/.env"; do
            i=$((i + 1)); [ "$i" -ge 180 ] && { echo "!!! Akaunting was not installed by the server after 180s" >&2; exit 1; }
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
    $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "akaunting", (int) (getenv("DB_PORT") ?: 3306));
    exit($c ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at ${DB_HOST:-db} not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*)
        if ! grep -q '^APP_INSTALLED=true' "$STORAGE/.env"; then
            # Akaunting's installer: writes .env (APP_KEY, DB_*), migrates,
            # creates the company and the admin user — what the web
            # installer at /install does, driven by the variables below.
            echo "==> running artisan install"
            ephpm php artisan install --no-interaction \
                --db-host="${DB_HOST:-db}" --db-port="${DB_PORT:-3306}" \
                --db-name="${DB_DATABASE:-akaunting}" --db-username="${DB_USERNAME:-akaunting}" \
                --db-password="${DB_PASSWORD:-}" \
                --company-name="${AKAUNTING_COMPANY_NAME:-My Company}" \
                --company-email="${AKAUNTING_COMPANY_EMAIL:-my@company.com}" \
                --admin-email="${AKAUNTING_ADMIN_EMAIL:-admin@example.com}" \
                --admin-password="${AKAUNTING_ADMIN_PASSWORD:-changeme}" \
                --locale="${APP_LOCALE:-en-GB}"
        else
            # upgrades: apply pending migrations
            ephpm php artisan migrate --force --no-interaction
        fi
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
