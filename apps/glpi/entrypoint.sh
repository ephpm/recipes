#!/bin/bash
# Container entrypoint: the official glpi/glpi image's entrypoint
# (init-volumes-directories.sh, wait-for-db.sh, install.sh) with Apache and
# supervisord replaced by ePHPm.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh cron            -> GLPI's cron every 60 s (the official
#                                    image's glpi-cron program), once the
#                                    server has installed the database
#   entrypoint.sh <command...>    -> run <command>
set -euo pipefail

CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd /var/www/glpi

# Missing volume (sub)directories.
for dir in "$GLPI_CONFIG_DIR" "$GLPI_VAR_DIR" "$GLPI_MARKETPLACE_DIR" "$GLPI_LOG_DIR" \
    "$GLPI_VAR_DIR"/{_cache,_cron,_dumps,_graphs,_locales,_lock,_pictures,_plugins,_rss,_sessions,_tmp,_uploads,_inventories}; do
    mkdir -p -- "$dir"
done

wait_for_db() {
    [ -n "${GLPI_DB_HOST:-}" ] || return 0
    echo "==> waiting for database at ${GLPI_DB_HOST}:${GLPI_DB_PORT:-3306}"
    local i=0
    until ephpm php -r '
        mysqli_report(MYSQLI_REPORT_OFF);
        $c = @mysqli_connect(getenv("GLPI_DB_HOST"), getenv("GLPI_DB_USER") ?: "", getenv("GLPI_DB_PASSWORD") ?: "", getenv("GLPI_DB_NAME") ?: "", (int) (getenv("GLPI_DB_PORT") ?: 3306));
        exit($c ? 0 : 1);
    ' 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
        sleep 2
    done
}

glpi_installed() {
    [ -f "$GLPI_CONFIG_DIR/config_db.php" ] || return 1
    # db:check exit codes: 0 ok, 1-4 schema diff warnings, 5+ connection/version/no tables
    local rc=0
    ephpm php bin/console db:check --quiet || rc=$?
    [ "$rc" -lt 5 ]
}

case "${1:-}" in
    ""|-*)
        rm -f "$GLPI_CONFIG_DIR/.ephpm-ready"     # the cron sidecar waits for it
        wait_for_db
        # Same rules as the official install.sh: no complete DB settings → no automation.
        if [ -z "${GLPI_DB_HOST:-}" ] || [ -z "${GLPI_DB_NAME:-}" ] || [ -z "${GLPI_DB_USER:-}" ] || [ -z "${GLPI_DB_PASSWORD:-}" ]; then
            echo "==> database settings incomplete: skipping auto-install/update (use the web installer)"
        elif ! glpi_installed; then
            if [ "$GLPI_SKIP_AUTOINSTALL" != true ]; then
                echo "==> installing GLPI (bin/console database:install) — this takes a minute"
                ephpm php bin/console database:install \
                    --db-host="$GLPI_DB_HOST" --db-port="${GLPI_DB_PORT:-3306}" \
                    --db-name="$GLPI_DB_NAME" --db-user="$GLPI_DB_USER" --db-password="$GLPI_DB_PASSWORD" \
                    --no-interaction --quiet
                echo "==> GLPI installed — log in as glpi / glpi and change the default passwords"
            fi
        elif [ "$GLPI_SKIP_AUTOUPDATE" != true ]; then
            echo "==> updating the GLPI database (bin/console database:update)"
            ephpm php bin/console database:update --no-interaction --quiet
        fi
        touch "$GLPI_CONFIG_DIR/.ephpm-ready"
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    cron)
        wait_for_db
        # wait until the server has installed/updated the database (config_db.php
        # appears early in database:install, so it is not a signal on its own)
        until [ -f "$GLPI_CONFIG_DIR/.ephpm-ready" ]; do sleep 5; done
        echo "==> GLPI cron: front/cron.php every 60 s"
        while :; do
            ephpm php front/cron.php 2>&1 || echo "!!! front/cron.php exited with $?" >&2
            sleep 60
        done
        ;;
    *) exec "$@" ;;
esac
