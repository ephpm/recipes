#!/bin/sh
# Container entrypoint: seed the config volume, prepare the first-start
# install (config/autoconfig.php, as the official image does), wait for the
# database, then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> once Nextcloud is installed
#                                    (the `cron` service)
#
# The install runs on the FIRST HTTP REQUEST, through the web installer, not
# through `occ maintenance:install`: Nextcloud's console refuses to load its
# config under `ephpm php` (see README, "Known limitations").
set -eu

HTML=/var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
installed() { [ -f "$HTML/config/config.php" ] && grep -q "'installed' => true" "$HTML/config/config.php"; }

case "${1:-}" in
    ""|-*) ;;
    *)
        i=0
        until installed; do
            i=$((i + 1)); [ "$i" -ge 3600 ] && { echo "!!! Nextcloud is not installed after an hour" >&2; exit 1; }
            sleep 1
        done
        exec "$@"
        ;;
esac

# config/ is a volume: seed what the release ships, and the ePHPm fragment.
for f in /usr/local/share/nextcloud/config/*; do
    [ -e "$HTML/config/$(basename "$f")" ] || cp -a "$f" "$HTML/config/"
done
cp /usr/local/share/nextcloud/ephpm.config.php "$HTML/config/ephpm.config.php"
mkdir -p "$HTML/data" "$HTML/custom_apps"

if ! installed; then
    # The official image's auto-configuration: with the database and the
    # admin account given, the installer runs by itself on the first request.
    ephpm php -r '
        $c = ["directory" => getenv("NEXTCLOUD_DATA_DIR") ?: "/var/www/html/data"];
        if (getenv("MYSQL_HOST")) {
            $c += ["dbtype" => "mysql", "dbhost" => getenv("MYSQL_HOST"),
                   "dbname" => getenv("MYSQL_DATABASE") ?: "nextcloud",
                   "dbuser" => getenv("MYSQL_USER") ?: "nextcloud",
                   "dbpass" => getenv("MYSQL_PASSWORD") ?: "",
                   "dbtableprefix" => getenv("NEXTCLOUD_TABLE_PREFIX") ?: "oc_"];
        }
        if (getenv("NEXTCLOUD_ADMIN_USER") && getenv("NEXTCLOUD_ADMIN_PASSWORD")) {
            $c += ["adminlogin" => getenv("NEXTCLOUD_ADMIN_USER"), "adminpass" => getenv("NEXTCLOUD_ADMIN_PASSWORD")];
        }
        file_put_contents("/var/www/html/config/autoconfig.php", "<?php\n\$AUTOCONFIG = " . var_export($c, true) . ";\n");
    '
    echo "==> wrote config/autoconfig.php; Nextcloud installs on the first request"
fi

if [ "${MYSQL_HOST:-}" ]; then
    echo "==> waiting for database at $MYSQL_HOST"
    i=0
    until ephpm php -r '
        [$h, $p] = array_pad(explode(":", getenv("MYSQL_HOST"), 2), 2, 3306);
        mysqli_report(MYSQLI_REPORT_OFF);
        exit(@mysqli_connect($h, getenv("MYSQL_USER"), getenv("MYSQL_PASSWORD"), getenv("MYSQL_DATABASE"), (int) $p) ? 0 : 1);
    ' 2>/dev/null; do
        i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! database at $MYSQL_HOST not reachable after 60 tries" >&2; exit 1; }
        sleep 2
    done
fi

exec ephpm serve --config "$CONFIG" "$@"
