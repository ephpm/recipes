#!/bin/sh
# Container entrypoint: seed the volumes, wait for the database, optionally
# run the archiver on a schedule, then ePHPm in the foreground. The
# MATOMO_DATABASE_* variables (same names as the official image) prefill the
# web installer and are read by Matomo's FormDatabaseSetup.
set -eu

HTML=/var/www/html
SEED=/usr/local/share/matomo
cd "$HTML"

seed() { # seed <volume dir> <pristine dir>
    if [ -z "$(ls -A "$1" 2>/dev/null)" ]; then
        mkdir -p "$1" && cp -a "$2/." "$1/"
    fi
}
seed "$HTML/config" "$SEED/config"
seed "$HTML/plugins" "$SEED/plugins"
seed "$HTML/misc/user" "$SEED/user"
mkdir -p "$HTML/tmp"

# Wait for the database (the installer and the console both need it).
DB_HOST="${MATOMO_DATABASE_HOST:-db}"
echo "==> waiting for database at $DB_HOST"
i=0
until ephpm php -r '
    [$h, $p] = array_pad(explode(":", $argv[1], 2), 2, 3306);
    mysqli_report(MYSQLI_REPORT_OFF);
    exit(@mysqli_connect($h, getenv("MATOMO_DATABASE_USERNAME") ?: "root", getenv("MATOMO_DATABASE_PASSWORD") ?: "", getenv("MATOMO_DATABASE_DBNAME") ?: "matomo", (int) $p) ? 0 : 1);
' -- "$DB_HOST" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at $DB_HOST not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

# MATOMO_ARCHIVE_INTERVAL=3600: run `console core:archive` in the background
# every N seconds (Matomo's recommended cron job; empty/unset = browser-
# triggered archiving, Matomo's default). Only once config/config.ini.php
# exists, i.e. after the installer has run.
if [ -n "${MATOMO_ARCHIVE_INTERVAL:-}" ]; then
    echo "==> core:archive scheduled every ${MATOMO_ARCHIVE_INTERVAL}s"
    (
        while :; do
            sleep "$MATOMO_ARCHIVE_INTERVAL"
            [ -f config/config.ini.php ] || continue
            ephpm php console core:archive --url="${MATOMO_ARCHIVE_URL:-http://127.0.0.1:8080/}" >/dev/null \
                || echo "!!! core:archive failed" >&2
        done
    ) &
fi

exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@"
