#!/bin/sh
# Container entrypoint: wait for the database, install Elgg with elgg-cli on
# the first start (or run pending upgrades afterwards), then ePHPm in the
# foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after waiting for the DB
#                                    (the cron service: `elgg-cli cron` in a loop)
set -eu

ROOT=/var/www/elgg
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
SETTINGS="$ROOT/elgg-config/settings.php"
CLI=elgg-cli                     # /usr/local/bin/elgg-cli (see that file)

: "${ELGG_DB_HOST:=db}" "${ELGG_DB_PORT:=3306}" "${ELGG_DB_NAME:=elgg}" "${ELGG_DB_USER:=elgg}" "${ELGG_DB_PASSWORD:=}"
export ELGG_DB_HOST ELGG_DB_PORT ELGG_DB_NAME ELGG_DB_USER ELGG_DB_PASSWORD

echo "==> waiting for database at ${ELGG_DB_HOST}:${ELGG_DB_PORT}"
i=0
until ephpm php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    $c = @mysqli_connect(getenv("ELGG_DB_HOST"), getenv("ELGG_DB_USER"), getenv("ELGG_DB_PASSWORD"), getenv("ELGG_DB_NAME"), (int) getenv("ELGG_DB_PORT"));
    exit($c ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at ${ELGG_DB_HOST} not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*)
        if [ ! -f "$SETTINGS" ]; then
            : "${ELGG_WWWROOT:?set ELGG_WWWROOT to the site URL, with a trailing slash}"
            : "${ELGG_ADMIN_PASSWORD:?set ELGG_ADMIN_PASSWORD (Elgg 7 requires at least 16 characters) for the first start}"
            echo "==> installing Elgg (elgg-cli install)"
            cat > /tmp/elgg-install.php <<'PHP'
<?php
return [
    'displayname' => getenv('ELGG_ADMIN_DISPLAYNAME') ?: 'Administrator',
    'username'    => getenv('ELGG_ADMIN_USERNAME') ?: 'admin',
    'password'    => getenv('ELGG_ADMIN_PASSWORD'),
    'email'       => getenv('ELGG_ADMIN_EMAIL') ?: 'admin@example.com',
    'dbhost'      => getenv('ELGG_DB_HOST'),
    'dbport'      => getenv('ELGG_DB_PORT'),
    'dbuser'      => getenv('ELGG_DB_USER'),
    'dbpassword'  => getenv('ELGG_DB_PASSWORD'),
    'dbname'      => getenv('ELGG_DB_NAME'),
    'dbprefix'    => getenv('ELGG_DB_PREFIX') ?: 'elgg_',
    'sitename'    => getenv('ELGG_SITE_NAME') ?: 'Elgg on ePHPm',
    'siteemail'   => getenv('ELGG_SITE_EMAIL') ?: (getenv('ELGG_ADMIN_EMAIL') ?: 'admin@example.com'),
    'wwwroot'     => getenv('ELGG_WWWROOT'),
    'dataroot'    => '/var/lib/elgg/data/',
    'timezone'    => getenv('ELGG_TIMEZONE') ?: 'UTC',
];
PHP
            $CLI install --config=/tmp/elgg-install.php --no-ansi
            rm -f /tmp/elgg-install.php
        else
            echo "==> running pending upgrades (elgg-cli upgrade)"
            $CLI upgrade async --no-ansi || echo "!!! elgg-cli upgrade failed; see above" >&2
        fi
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
