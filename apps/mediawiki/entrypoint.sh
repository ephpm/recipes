#!/bin/sh
# Container entrypoint: first-run install through MediaWiki's CLI installer
# (when MEDIAWIKI_ADMIN_PASS is set and no LocalSettings.php exists yet), then
# ePHPm in the foreground. LocalSettings.php lives in the `config` volume.
set -eu

HTML=/var/www/html
CONF=/var/www/config/LocalSettings.php
cd "$HTML"

# images/ lives in a volume; seed it (its .htaccess and README) if empty.
if [ -z "$(ls -A images 2>/dev/null)" ]; then
    cp -a /usr/local/share/mediawiki-images/. images/
fi

DB_TYPE="${MEDIAWIKI_DB_TYPE:-mysql}"
DB_HOST="${MEDIAWIKI_DB_HOST:-db}"

# Wait for an external MySQL/MariaDB (MediaWiki's own SQLite needs nothing).
if [ "$DB_TYPE" = "mysql" ]; then
    echo "==> waiting for database at $DB_HOST"
    i=0
    until php -r '
        [$h, $p] = array_pad(explode(":", $argv[1], 2), 2, 3306);
        mysqli_report(MYSQLI_REPORT_OFF);
        exit(@mysqli_connect($h, getenv("MEDIAWIKI_DB_USER") ?: "root", getenv("MEDIAWIKI_DB_PASSWORD") ?: "", getenv("MEDIAWIKI_DB_NAME") ?: "mediawiki", (int) $p) ? 0 : 1);
    ' -- "$DB_HOST" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database at $DB_HOST not reachable after 60 tries" >&2; exit 1; }
        sleep 2
    done
fi

if [ ! -f "$CONF" ] && [ -n "${MEDIAWIKI_ADMIN_PASS:-}" ]; then
    echo "==> installing MediaWiki (maintenance/run.php install)"
    install() { # install <db options…>
        php maintenance/run.php install --confpath /var/www/config \
            --server "${MEDIAWIKI_SITE_SERVER:-http://localhost:8080}" --scriptpath "" \
            --lang "${MEDIAWIKI_SITE_LANG:-en}" --pass "$MEDIAWIKI_ADMIN_PASS" "$@" \
            "${MEDIAWIKI_SITE_NAME:-MediaWiki}" "${MEDIAWIKI_ADMIN_USER:-admin}"
    }
    if [ "$DB_TYPE" = "sqlite" ]; then
        install --dbtype sqlite --dbpath /var/www/data
    else
        install --dbtype mysql --dbserver "$DB_HOST" --dbname "${MEDIAWIKI_DB_NAME:-mediawiki}" \
                --dbuser "${MEDIAWIKI_DB_USER:-mediawiki}" --dbpass "${MEDIAWIKI_DB_PASSWORD:-}" \
                --installdbuser "${MEDIAWIKI_DB_USER:-mediawiki}" --installdbpass "${MEDIAWIKI_DB_PASSWORD:-}"
    fi
    cat >> "$CONF" <<'EOF'

## ePHPm recipe: no PATH_INFO and no regex rewrites, so plain index.php?title= URLs
$wgUsePathInfo = false;
## uploads into the images volume
$wgEnableUploads = true;
EOF
    echo "==> MediaWiki installed; LocalSettings.php written to /var/www/config"
fi

# MediaWiki looks for LocalSettings.php next to index.php.
if [ -f "$CONF" ]; then
    ln -sf "$CONF" "$HTML/LocalSettings.php"
else
    rm -f "$HTML/LocalSettings.php"
    echo "==> no LocalSettings.php yet: the web installer is at /mw-config/ (save the generated file into the config volume), or set MEDIAWIKI_ADMIN_PASS for a CLI install"
fi

exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@"
