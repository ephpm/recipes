#!/bin/bash
# Container entrypoint: .env with a generated APP_KEY in the storage volume,
# wait for the database, `freescout:after-app-update` (cache + migrations),
# the first admin user, then ePHPm.
#
#   entrypoint.sh               -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh scheduler     -> artisan schedule:run every minute (sidecar)
#   entrypoint.sh queue         -> artisan queue:work (sidecar)
#   entrypoint.sh <command...>  -> run <command>
set -euo pipefail

APP=/app
STORAGE=$APP/storage
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$APP"

# storage/ is a volume: seed what the release ships when it is empty.
[ -d "$STORAGE/framework" ] || cp -a /usr/local/share/freescout-storage/. "$STORAGE/"
mkdir -p "$STORAGE/app/public" "$STORAGE/framework/cache" "$STORAGE/framework/sessions" \
    "$STORAGE/framework/views" "$STORAGE/logs" "$APP/bootstrap/cache"

wait_for_db() {
    echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
    local i=0
    until ephpm php -r '
        $c = getenv("DB_CONNECTION") ?: "mysql";
        $dsn = ($c === "pgsql" ? "pgsql" : "mysql") . ":host=" . (getenv("DB_HOST") ?: "db") . ";port=" . (getenv("DB_PORT") ?: ($c === "pgsql" ? 5432 : 3306)) . ";dbname=" . getenv("DB_DATABASE");
        try { new PDO($dsn, getenv("DB_USERNAME"), getenv("DB_PASSWORD")); } catch (Throwable $e) { exit(1); }
    ' 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
        sleep 2
    done
}

case "${1:-}" in
    ""|-*)
        rm -f "$STORAGE/.ephpm-ready"           # the sidecars wait for it
        # .env holds only what must survive restarts (APP_KEY); everything
        # else comes from the container environment, which wins over .env.
        if [ ! -s "$STORAGE/.env" ] || ! grep -q '^APP_KEY=base64:' "$STORAGE/.env"; then
            key="${APP_KEY:-base64:$(ephpm php -r 'echo base64_encode(random_bytes(32));')}"
            printf 'APP_KEY=%s\n' "$key" > "$STORAGE/.env"
            echo "==> generated APP_KEY into storage/.env"
        fi
        wait_for_db
        echo "==> freescout:after-app-update (config cache, migrations)"
        ephpm php artisan freescout:after-app-update --no-interaction
        if [ ! -f "$STORAGE/.ephpm-admin-created" ]; then
            echo "==> creating the admin user (${FREESCOUT_ADMIN_EMAIL:-admin@example.com})"
            ephpm php artisan freescout:create-user --role=admin --no-interaction \
                --firstName="${FREESCOUT_ADMIN_FIRST_NAME:-Help}" --lastName="${FREESCOUT_ADMIN_LAST_NAME:-Desk}" \
                --email="${FREESCOUT_ADMIN_EMAIL:-admin@example.com}" \
                --password="${FREESCOUT_ADMIN_PASSWORD:?FREESCOUT_ADMIN_PASSWORD is required for the first start}"
            touch "$STORAGE/.ephpm-admin-created"
        fi
        touch "$STORAGE/.ephpm-ready"
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    scheduler|queue)
        until [ -f "$STORAGE/.ephpm-ready" ]; do sleep 3; done
        if [ "$1" = scheduler ]; then
            echo "==> scheduler: artisan schedule:run every minute"
            # --no-interaction: FreeScout then does not try to launch its own
            # `queue:work` daemon (it would re-invoke PHP through PHP_BINARY,
            # which is `ephpm` here — ephpm#558); the queue service runs it.
            while :; do
                ephpm php artisan schedule:run --no-interaction || echo "!!! schedule:run failed" >&2
                sleep 60
            done
        fi
        # The queues FreeScout's scheduler would start the worker on:
        # app.queue_work_params plus the per-install identifier md5(APP_KEY).
        ident="$(ephpm php -r 'foreach (file("/app/storage/.env") as $l) { if (str_starts_with($l, "APP_KEY=")) { echo md5(trim(substr($l, 8))); } }')"
        [ -n "${APP_KEY:-}" ] && ident="$(ephpm php -r 'echo md5(getenv("APP_KEY"));')"
        echo "==> queue worker: emails,default,$ident"
        exec ephpm php artisan queue:work --queue="emails,default,$ident" --sleep=5 --tries=1 --timeout=1800
        ;;
    *) exec "$@" ;;
esac
