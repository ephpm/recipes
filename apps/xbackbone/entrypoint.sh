#!/bin/sh
# config.php lives in the storage volume (symlinked into place). On the first
# start the web installer (a single POST to /install/) is run once on a private
# loopback port from the environment, then ePHPm serves.
set -eu
cd /var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
mkdir -p storage resources/database
ln -sfn /var/www/html/storage/config.php config.php

if [ ! -f storage/config.php ] && [ -n "${XBACKBONE_ADMIN_PASSWORD:-}" ]; then
    echo "==> installing XBackBone"
    ephpm serve --config "$CONFIG" --listen 127.0.0.1:8099 >/tmp/install-server.log 2>&1 &
    srv=$!
    i=0
    until ephpm php -r 'exit(@file_get_contents("http://127.0.0.1:8099/install/") === false ? 1 : 0);' 2>/dev/null; do
        i=$((i + 1)); [ "$i" -ge 30 ] && { echo "!!! installer server did not start" >&2; exit 1; }
        sleep 1
    done
    ephpm php -r '
        $e = static fn (string $k, string $d = ""): string => (string) (getenv($k) ?: $d);
        $form = http_build_query(["base_url" => $e("XBACKBONE_BASE_URL", "http://localhost:8080"), "connection" => "sqlite",
            "dsn" => "/var/www/html/resources/database/xbackbone.db", "db_user" => "", "db_password" => "",
            "storage_driver" => "local", "storage_path" => "/var/www/html/storage",
            "email" => $e("XBACKBONE_ADMIN_EMAIL", "admin@example.org"), "password" => $e("XBACKBONE_ADMIN_PASSWORD")]);
        file_get_contents("http://127.0.0.1:8099/install/", false, stream_context_create(["http" => [
            "method" => "POST", "header" => "Content-Type: application/x-www-form-urlencoded", "content" => $form, "timeout" => 120, "ignore_errors" => true]]));
    ' >/dev/null
    kill "$srv" 2>/dev/null || true
    wait "$srv" 2>/dev/null || true
    [ -f storage/config.php ] || { echo "!!! the installer did not write config.php" >&2; exit 1; }
    echo "==> XBackBone installed (user: admin)"
fi
case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
