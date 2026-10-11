#!/bin/sh
# Container entrypoint: php.ini lines from the environment, a cookie secret,
# optional base64 configs (same variables as the official image), then ePHPm.
set -eu

CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
mkdir -p /run/ephpm /etc/phpmyadmin/conf.d /var/www/html/tmp

# UPLOAD_LIMIT (default 2048K as in the official image), TZ → php.ini
{
    printf 'upload_max_filesize = %s\n' "${UPLOAD_LIMIT:-2048K}"
    printf 'post_max_size = %s\n' "${UPLOAD_LIMIT:-2048K}"
    printf 'date.timezone = "%s"\n' "${TZ:-UTC}"
    [ -z "${HIDE_PHP_VERSION:-}" ] || printf 'expose_php = Off\n'
} > /run/ephpm/php.ini

# Cookie-auth encryption key: a fresh one per container start unless the file
# is mounted (or PMA_BLOWFISH_SECRET is set) — exactly like the official image.
if [ ! -f /etc/phpmyadmin/config.secret.inc.php ]; then
    ephpm php -r 'echo "<?php\n\$cfg[\"blowfish_secret\"] = ", var_export(bin2hex(random_bytes(32)), true), ";\n";' \
        > /etc/phpmyadmin/config.secret.inc.php
fi

if [ -n "${PMA_CONFIG_BASE64:-}" ]; then
    echo "==> using config.inc.php from PMA_CONFIG_BASE64"
    printf '%s' "$PMA_CONFIG_BASE64" | base64 -d > /etc/phpmyadmin/config.inc.php
fi
if [ -n "${PMA_USER_CONFIG_BASE64:-}" ]; then
    echo "==> using config.user.inc.php from PMA_USER_CONFIG_BASE64"
    printf '%s' "$PMA_USER_CONFIG_BASE64" | base64 -d > /etc/phpmyadmin/config.user.inc.php
fi

exec ephpm serve --config "$CONFIG" "$@"
