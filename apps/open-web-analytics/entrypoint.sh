#!/bin/sh
# Container entrypoint: seed the owa-data volume, write owa-config.php on the
# first start, wait for the database, install OWA with cli.php when the
# schema is missing (or apply pending updates), then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after waiting for the DB
#                                    (the cron service: `owa-cli cmd=schedule-run`)
set -eu

OWA=/var/www/owa
DATA=$OWA/owa-data
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

: "${OWA_DB_HOST:=db}" "${OWA_DB_PORT:=3306}" "${OWA_DB_NAME:=owa}" "${OWA_DB_USER:=owa}" "${OWA_DB_PASSWORD:=}"
export OWA_DB_HOST OWA_DB_PORT OWA_DB_NAME OWA_DB_USER OWA_DB_PASSWORD

# owa-data (config, caches, logs) is a volume.
[ -e "$DATA/index.php" ] || cp -a /usr/local/share/owa-data/. "$DATA/"
mkdir -p "$DATA/caches" "$DATA/logs"

# owa-config.php: database settings and the public URL from the environment
# (read on every request), keys and salts generated once per installation.
if [ ! -f "$DATA/owa-config.php" ]; then
    : "${OWA_PUBLIC_URL:?set OWA_PUBLIC_URL to the URL OWA is served at, with a trailing slash}"
    ephpm php -r '
        $k = fn () => bin2hex(random_bytes(32));
        $c = "<?php\n"
           . "// Written by the ePHPm recipe entrypoint on first start. Database and URL\n"
           . "// settings come from the environment; the keys below are per installation.\n"
           . "define(\"OWA_DB_TYPE\", \"mysql\");\n";
        foreach (["OWA_DB_NAME", "OWA_DB_HOST", "OWA_DB_USER", "OWA_DB_PORT", "OWA_DB_PASSWORD", "OWA_PUBLIC_URL"] as $n) {
            $c .= "define(\"$n\", getenv(\"$n\"));\n";
        }
        foreach (["OWA_NONCE_KEY", "OWA_NONCE_SALT", "OWA_AUTH_KEY", "OWA_AUTH_SALT"] as $n) {
            $c .= "define(\"$n\", " . var_export($k(), true) . ");\n";
        }
        file_put_contents($argv[1], $c);
    ' "$DATA/owa-config.php"
    chmod 640 "$DATA/owa-config.php"
    echo "==> wrote owa-data/owa-config.php"
fi

echo "==> waiting for database at ${OWA_DB_HOST}:${OWA_DB_PORT}"
i=0
until ephpm php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    $c = @mysqli_connect(getenv("OWA_DB_HOST"), getenv("OWA_DB_USER"), getenv("OWA_DB_PASSWORD"), getenv("OWA_DB_NAME"), (int) getenv("OWA_DB_PORT"));
    exit($c ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at ${OWA_DB_HOST} not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

installed() {
    ephpm php -r '
        mysqli_report(MYSQLI_REPORT_OFF);
        $c = mysqli_connect(getenv("OWA_DB_HOST"), getenv("OWA_DB_USER"), getenv("OWA_DB_PASSWORD"), getenv("OWA_DB_NAME"), (int) getenv("OWA_DB_PORT"));
        $r = $c ? mysqli_query($c, "SELECT 1 FROM owa_user WHERE role = \"admin\" LIMIT 1") : false;
        exit($r && mysqli_num_rows($r) ? 0 : 1);
    ' 2>/dev/null
}

case "${1:-}" in
    ""|-*)
        if ! installed; then
            : "${OWA_ADMIN_PASSWORD:?set OWA_ADMIN_PASSWORD for the first start}"
            echo "==> installing OWA (cli.php cmd=install)"
            owa-cli cmd=install user_id="${OWA_ADMIN_USER:-admin}" \
                email_address="${OWA_ADMIN_EMAIL:-admin@example.com}" \
                domain="${OWA_SITE_DOMAIN:-http://localhost/}" \
                description="${OWA_SITE_DESCRIPTION:-Default site}"
            installed || { echo "!!! OWA install did not create the admin user (see above)" >&2; exit 1; }
            # cmd=install sets the admin password to the database password;
            # replace it with OWA_ADMIN_PASSWORD.
            owa-cli cmd=change-password user="${OWA_ADMIN_USER:-admin}" password="$OWA_ADMIN_PASSWORD"
        else
            echo "==> applying pending updates (cli.php cmd=update)"
            owa-cli cmd=update || echo "!!! cmd=update failed; see above" >&2
        fi
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
