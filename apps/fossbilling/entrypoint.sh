#!/bin/sh
# config.php is kept in the data volume (symlinked into place). On the first
# start FOSSBilling's web installer (one POST to install/install.php?a=install)
# is run on a private loopback port from the environment.
set -eu
cd /var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
[ -e data/cache ] || cp -a /usr/local/share/fossbilling/data/. data/
ln -sfn /var/www/html/data/config.php config.php

echo "==> waiting for database"
i=0
until php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    exit(@mysqli_connect(getenv("FOSSBILLING_DB_HOST") ?: "db", getenv("FOSSBILLING_DB_USER") ?: "fossbilling", getenv("FOSSBILLING_DB_PASSWORD") ?: "", getenv("FOSSBILLING_DB_NAME") ?: "fossbilling") ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! database not reachable" >&2; exit 1; }
    sleep 2
done

if [ ! -s data/config.php ] && [ -n "${FOSSBILLING_ADMIN_PASSWORD:-}" ]; then
    rm -f data/config.php
    echo "==> installing FOSSBilling"
    ephpm serve --config "$CONFIG" --listen 127.0.0.1:8099 >/tmp/install-server.log 2>&1 &
    srv=$!
    i=0
    until php -r 'exit(@file_get_contents("http://127.0.0.1:8099/install/index.php") === false ? 1 : 0);' 2>/dev/null; do
        i=$((i + 1)); [ "$i" -ge 30 ] && { echo "!!! installer server did not start" >&2; exit 1; }
        sleep 1
    done
    php -r '
        $e = static fn (string $k, string $d = ""): string => (string) (getenv($k) ?: $d);
        $form = http_build_query([
            "system_url" => $e("FOSSBILLING_URL", "http://localhost:8080/"), "currency_code" => "USD",
            "database_hostname" => $e("FOSSBILLING_DB_HOST", "db"), "database_port" => "3306",
            "database_name" => $e("FOSSBILLING_DB_NAME", "fossbilling"),
            "database_username" => $e("FOSSBILLING_DB_USER", "fossbilling"), "database_password" => $e("FOSSBILLING_DB_PASSWORD"),
            "admin_name" => "Administrator", "admin_email" => $e("FOSSBILLING_ADMIN_EMAIL", "admin@example.org"),
            "admin_password" => $e("FOSSBILLING_ADMIN_PASSWORD"),
        ]);
        $out = file_get_contents("http://127.0.0.1:8099/install/install.php?a=install", false, stream_context_create(["http" => [
            "method" => "POST", "header" => "Content-Type: application/x-www-form-urlencoded", "content" => $form, "timeout" => 300, "ignore_errors" => true]]));
        file_put_contents("/tmp/install.out", (string) $out);
    '
    kill "$srv" 2>/dev/null || true
    wait "$srv" 2>/dev/null || true
    if [ ! -s data/config.php ] && [ ! -s config.php ]; then
        echo "!!! the installer did not write config.php:" >&2; head -c 600 /tmp/install.out >&2; exit 1
    fi
    echo "==> FOSSBilling installed"
fi
case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
