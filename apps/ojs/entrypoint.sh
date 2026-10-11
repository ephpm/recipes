#!/bin/sh
# Container entrypoint: write config.inc.php from the PKP_* variables (the
# official pkp/ojs image's names) the first time, wait for the database,
# then ePHPm in the foreground. The schema and the admin account are created
# by OJS's web installer on the first visit (or by the scripted POST
# test.sh sends — the same request the official image's PKP_CLI_INSTALL=1
# mode makes). With arguments (the `cron` service) it runs them instead.
set -eu

cd /var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# public/ (journal logos, uploads) lives in a volume; seed it when created empty.
[ -n "$(ls -A public 2>/dev/null)" ] || cp -a /usr/local/share/ojs-public/. public/
mkdir -p /var/www/files cache/t_cache cache/t_compile cache/t_config cache/_db

PKP_DB_DRIVER="${PKP_DB_DRIVER:-mysqli}"
PKP_DB_HOST="${PKP_DB_HOST:-db}"
PKP_DB_NAME="${PKP_DB_NAME:-pkp}"
PKP_DB_USER="${PKP_DB_USER:-pkp}"
PKP_DB_PASSWORD="${PKP_DB_PASSWORD:-changeMePlease}"
PKP_BASE_URL="${PKP_BASE_URL:-http://localhost:8080}"

# config.inc.php lives in the config volume (the installer rewrites it in
# place with installed = On and the database settings); it is written once,
# since the secrets in it must stay stable, and linked into the app root.
mkdir -p /var/www/config
ln -sfn /var/www/config/config.inc.php config.inc.php
if [ ! -f /var/www/config/config.inc.php ]; then
    echo "==> writing config.inc.php from the environment"
    salt="$(ephpm php -r 'echo bin2hex(random_bytes(32));')"
    api_secret="$(ephpm php -r 'echo bin2hex(random_bytes(32));')"
    sed -e "s|^installed = .*|installed = Off|" \
        -e "s|^base_url = .*|base_url = \"$PKP_BASE_URL\"|" \
        -e "s|^driver = .*|driver = $PKP_DB_DRIVER|" \
        -e "s|^host = .*|host = $PKP_DB_HOST|" \
        -e "s|^username = .*|username = $PKP_DB_USER|" \
        -e "s|^password = .*|password = $PKP_DB_PASSWORD|" \
        -e "s|^name = .*|name = $PKP_DB_NAME|" \
        -e "s|^files_dir = .*|files_dir = /var/www/files|" \
        -e "s|^salt = .*|salt = \"$salt\"|" \
        -e "s|^api_key_secret = .*|api_key_secret = \"$api_secret\"|" \
        -e "s|^allowed_hosts = .*|allowed_hosts = \"${PKP_ALLOWED_HOSTS:-}\"|" \
        config.TEMPLATE.inc.php > /var/www/config/config.inc.php
    [ "${PKP_RESTFUL_URLS:-Off}" = "On" ] && sed -i 's|^restful_urls = .*|restful_urls = On|' config.inc.php
    [ -n "${PKP_SESSION_CHECK_IP:-}" ] && sed -i "s|^session_check_ip = .*|session_check_ip = $PKP_SESSION_CHECK_IP|" config.inc.php
fi

echo "==> waiting for database at $PKP_DB_HOST"
port=3306; case "$PKP_DB_DRIVER" in postgres*|pgsql) port=5432 ;; esac
i=0
until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$PKP_DB_HOST" "$port" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 90 ] && { echo "!!! database at $PKP_DB_HOST not reachable after 90 tries" >&2; exit 1; }
    sleep 2
done

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

if grep -q '^installed = On' config.inc.php; then
    echo "==> installed; running pending upgrades"
    ephpm php tools/upgrade.php check >/dev/null 2>&1 || true
else
    echo "==> not installed: open ${PKP_BASE_URL} to run the installer"
fi
echo "==> OJS is ready"

exec ephpm serve --config "$CONFIG"
