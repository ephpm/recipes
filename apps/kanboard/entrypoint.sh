#!/bin/sh
# Container entrypoint: wait for an external database, run the daily cron
# job in the background (the official image's crond: `0 8 * * * ./cli
# cronjob`), then ePHPm in the foreground.
set -eu

APP=/var/www/app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$APP"
mkdir -p data plugins

# Wait for an external MySQL/PostgreSQL (the embedded one starts with the
# server, and SQLite needs nothing).
case "${DB_DRIVER:-sqlite}" in
    mysql|postgres)
        host="${DB_HOSTNAME:-localhost}"
        case "$host" in 127.0.0.1*|localhost*) ;; *)
            echo "==> waiting for ${DB_DRIVER} at ${host}"
            i=0
            until ephpm php -r '
                $drv = getenv("DB_DRIVER") === "postgres" ? "pgsql" : "mysql";
                $port = getenv("DB_PORT") ?: ($drv === "pgsql" ? 5432 : 3306);
                try { new PDO("$drv:host=" . getenv("DB_HOSTNAME") . ";port=$port;dbname=" . getenv("DB_NAME"), getenv("DB_USERNAME"), getenv("DB_PASSWORD")); exit(0); }
                catch (Throwable $e) { exit(1); }
            ' 2>/dev/null; do
                i=$((i + 1))
                [ "$i" -ge 60 ] && { echo "!!! database at ${host} not reachable after 60 tries" >&2; exit 1; }
                sleep 2
            done ;;
        esac ;;
esac

# Daily cron job at CRON_HOUR:00 (default 08:00, as in the official image's
# crontab). CRON_HOUR="" disables it.
CRON_HOUR="${CRON_HOUR-8}"
if [ -n "$CRON_HOUR" ]; then
    echo "==> ./cli cronjob scheduled daily at ${CRON_HOUR}:00"
    (
        while :; do
            sleep $((60 - $(date +%S | sed 's/^0//')))
            if [ "$(date +%H | sed 's/^0//')" -eq "$((CRON_HOUR + 0))" ] && [ "$(date +%M)" = "00" ]; then
                ephpm php ./cli cronjob >/dev/null || echo "!!! cronjob failed" >&2
            fi
        done
    ) &
fi

exec ephpm serve --config "$CONFIG" "$@"
