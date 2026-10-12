#!/bin/sh
# Container entrypoint: seed the application volume, wait for the database,
# run SuiteCRM's silent installer on the first start, then ePHPm in the
# foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh cron            -> run cron.php every minute (the scheduler)
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

HTML=/var/www/html
cd "$HTML"

installed() { grep -qs "'installer_locked' => true" config.php; }

if [ ! -f index.php ]; then
    echo "==> seeding $HTML from the image"
    cp -a /usr/src/suitecrm/. "$HTML/"
fi

if [ "${1:-}" = "cron" ]; then
    # The web container runs the installer (config.php is written at its
    # start, the tables after); wait for its "done" marker.
    until [ -f .ephpm-ready ]; do sleep 5; done
    echo "==> running cron.php every 60 s"
    while :; do
        # PHP 8.4 deprecation notices from bundled libraries would flood the log
        php -d "error_reporting=E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED" -f cron.php || echo "cron.php exited with $?" >&2
        sleep 60
    done
fi

echo "==> waiting for database at ${SUITECRM_DB_HOST:-db}:${SUITECRM_DB_PORT:-3306}"
i=0
until php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    exit(@mysqli_connect(getenv("SUITECRM_DB_HOST") ?: "db", getenv("SUITECRM_DB_USER") ?: "suitecrm", getenv("SUITECRM_DB_PASSWORD") ?: "", getenv("SUITECRM_DB_NAME") ?: "suitecrm", (int) (getenv("SUITECRM_DB_PORT") ?: 3306)) ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

if ! installed; then
    echo "==> installing SuiteCRM (silent installer)"
    # Sessions without cookies: `ephpm php` reports headers as already sent
    # before any output (issues/wallabag.md), which makes session_start()
    # refuse cookie sessions.
    php -d session.use_cookies=0 /usr/local/share/suitecrm-si-install.php > /tmp/suitecrm-install.log 2>&1 || true
    if ! installed; then
        echo "!!! SuiteCRM installation failed:" >&2
        tail -40 /tmp/suitecrm-install.log >&2
        tail -40 install.log >&2 2>/dev/null || true
        exit 1
    fi
    echo "==> SuiteCRM installed"
fi

# Everything in this image runs as root (the web server too), so let
# cron.php run as root: SuiteCRM refuses by default because on a classic
# host root's files would be unwritable for the web server user.
if ! grep -qs "allowed_cron_users" config_override.php; then
    [ -f config_override.php ] || echo '<?php' > config_override.php
    echo '$sugar_config["cron"]["allowed_cron_users"] = ["root"];' >> config_override.php
fi
touch .ephpm-ready

case "${1:-}" in
    ""|-*) exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@" ;;
    *) exec "$@" ;;
esac
