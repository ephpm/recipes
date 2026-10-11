#!/bin/bash
# Container entrypoint: wait for the database, install Moodle with
# admin/cli/install_database.php on the first start (or run
# admin/cli/upgrade.php after an image upgrade), then ePHPm.
#
#   entrypoint.sh               -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh cron          -> admin/cli/cron.php every minute (sidecar)
#   entrypoint.sh <command...>  -> run <command>
set -euo pipefail

CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
DATA="${MOODLE_DATAROOT:-/var/moodledata}"
cd /var/www/moodle
mkdir -p "$DATA"

wait_for_db() {
    echo "==> waiting for database at ${MOODLE_DBHOST:-db}"
    local i=0
    until ephpm php -r '
        $t = getenv("MOODLE_DBTYPE") ?: "pgsql"; $h = getenv("MOODLE_DBHOST") ?: "db"; $p = getenv("MOODLE_DBPORT");
        $dsn = ($t === "pgsql" ? "pgsql" : "mysql") . ":host=$h" . ($p ? ";port=$p" : "") . ";dbname=" . (getenv("MOODLE_DBNAME") ?: "moodle");
        try { new PDO($dsn, getenv("MOODLE_DBUSER") ?: "moodle", getenv("MOODLE_DBPASS") ?: ""); } catch (Throwable $e) { exit(1); }
    ' 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
        sleep 2
    done
}

# Is the database installed? (admin/cli/cfg.php fails before installation.)
installed() { php admin/cli/cfg.php --name=version >/dev/null 2>&1; }

case "${1:-}" in
    ""|-*)
        rm -f "$DATA/.ephpm-ready"           # the cron sidecar waits for it
        wait_for_db
        if ! installed; then
            echo "==> installing Moodle (admin/cli/install_database.php) — this takes a few minutes"
            php admin/cli/install_database.php --agree-license \
                --lang="${MOODLE_LANG:-en}" \
                --adminuser="${MOODLE_ADMIN_USER:-admin}" \
                --adminpass="${MOODLE_ADMIN_PASSWORD:?MOODLE_ADMIN_PASSWORD is required for the first start}" \
                --adminemail="${MOODLE_ADMIN_EMAIL:-admin@example.com}" \
                --fullname="${MOODLE_SITE_FULLNAME:-Moodle on ePHPm}" \
                --shortname="${MOODLE_SITE_SHORTNAME:-moodle}" \
                --supportemail="${MOODLE_SUPPORT_EMAIL:-${MOODLE_ADMIN_EMAIL:-admin@example.com}}"
            echo "==> Moodle installed"
        else
            echo "==> upgrading the Moodle database if needed (admin/cli/upgrade.php)"
            php admin/cli/upgrade.php --non-interactive
        fi
        touch "$DATA/.ephpm-ready"
        # Moodle redirects every request whose port differs from the one in
        # $CFG->wwwroot, and takes the request's port from SERVER_PORT —
        # the port ePHPm listens on (nginx does the same; Apache instead
        # copies it from the Host header). So when MOODLE_WWWROOT names an
        # explicit port, listen on that port inside the container too, and
        # publish it 1:1 (compose.yml). See issues/moodle.md.
        port="$(ephpm php -r 'echo parse_url(getenv("MOODLE_WWWROOT") ?: "", PHP_URL_PORT) ?: "";')"
        if [ -n "$port" ] && [ "${MOODLE_SSLPROXY:-false}" != true ] && [ "$#" -eq 0 ]; then
            exec ephpm serve --config "$CONFIG" --listen "0.0.0.0:$port"
        fi
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    cron)
        wait_for_db
        until [ -f "$DATA/.ephpm-ready" ]; do sleep 5; done
        echo "==> Moodle cron: admin/cli/cron.php every minute"
        while :; do
            # one pass per minute, like a crontab entry (cron.php otherwise
            # keeps itself alive for $CFG->cron_keepalive seconds)
            php admin/cli/cron.php --keep-alive=0 2>&1 | grep -v '^Deprecated' | tail -n 3 \
                || echo "!!! admin/cli/cron.php failed" >&2
            sleep 60
        done
        ;;
    *) exec "$@" ;;
esac
