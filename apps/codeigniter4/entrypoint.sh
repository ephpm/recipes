#!/bin/sh
# First-run setup, then ePHPm in the foreground.
set -eu
cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
mkdir -p writable/cache writable/logs writable/session writable/uploads writable/debugbar

db_ok() {
    ephpm php -r '
        mysqli_report(MYSQLI_REPORT_OFF);
        exit(@mysqli_connect(getenv("database_default_hostname"), getenv("database_default_username"), getenv("database_default_password") ?: "", getenv("database_default_database"), (int) (getenv("database_default_port") ?: 3306)) ? 0 : 1);
    ' 2>/dev/null
}

migrate() {
    i=0
    until db_ok; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; return 1; }
        sleep 2
    done
    echo "==> running migrations"
    ephpm php spark migrate --all --no-header
}

if [ "${SKIP_MIGRATE:-0}" != "1" ]; then
    case "${database_default_hostname:-127.0.0.1}" in
        127.0.0.1|localhost) migrate & ;;    # embedded DB: up only once the server runs
        *) migrate ;;
    esac
fi

exec ephpm serve --config "$CONFIG" "$@"
