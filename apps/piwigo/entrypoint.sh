#!/bin/sh
# Container entrypoint: seed the volumes, wait for the database, install
# Piwigo unattended on the first start when PIWIGO_ADMIN_PASSWORD is set
# (otherwise the web installer at /install.php does it), then ePHPm in the
# foreground.
set -eu

HTML=/var/www/html
SEED=/usr/local/share/piwigo
cd "$HTML"

# local/ (database.inc.php, config.inc.php, custom CSS/languages) and
# galleries/ are volumes; put back what the release ships when they start
# out empty.
for d in local galleries; do
    [ -n "$(ls -A "$d" 2>/dev/null)" ] || cp -a "$SEED/$d/." "$d/"
done
mkdir -p _data upload local/config

# Piwigo's defaults switch display_errors on from PHP (`show_php_errors_on_frontend`)
# and report E_ALL; on PHP 8.5 its deprecation notices then land in pages
# and API responses before the headers (breaking the login cookie). Seed a
# production local config once; edit it in the `local` volume.
if [ ! -f local/config/config.inc.php ]; then
    cat > local/config/config.inc.php <<'PHP'
<?php
// Local Piwigo configuration (overrides include/config_default.inc.php).
// Errors go to the container log, not into pages.
$conf['show_php_errors'] = E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED;
$conf['show_php_errors_on_frontend'] = false;
PHP
fi

if [ ! -f local/config/database.inc.php ]; then
    DB_HOST="${PIWIGO_DB_HOST:-db}"
    echo "==> waiting for database at $DB_HOST"
    i=0
    until php -r '
        [$h, $p] = array_pad(explode(":", $argv[1], 2), 2, 3306);
        mysqli_report(MYSQLI_REPORT_OFF);
        exit(@mysqli_connect($h, getenv("PIWIGO_DB_USER") ?: "piwigo", getenv("PIWIGO_DB_PASSWORD") ?: "", getenv("PIWIGO_DB_NAME") ?: "piwigo", (int) $p) ? 0 : 1);
    ' -- "$DB_HOST" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database at $DB_HOST not reachable after 60 tries" >&2; exit 1; }
        sleep 2
    done
    if [ -n "${PIWIGO_ADMIN_PASSWORD:-}" ]; then
        echo "==> installing Piwigo"
        php "$SEED/install.php"
        [ -f local/config/database.inc.php ] || { echo "!!! the installer did not write local/config/database.inc.php" >&2; exit 1; }
    else
        echo "==> Piwigo is not installed yet: open /install.php"
    fi
fi

exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@"
