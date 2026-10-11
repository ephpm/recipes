#!/bin/bash
# Container entrypoint: the martialblog/limesurvey entrypoint without Apache
# — wait for the database, `console.php updatedb` (or `install` on an empty
# database), optional encryption keys from the environment, then ePHPm.
set -euo pipefail

WEB=/var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$WEB"

# upload/ is a volume: seed what the release ships when it is empty.
[ -n "$(ls -A upload 2>/dev/null)" ] || cp -a /usr/local/share/limesurvey-upload/. upload/
mkdir -p tmp/runtime tmp/assets tmp/upload /var/limesurvey

for v in DB_PASSWORD ADMIN_PASSWORD; do
    f="${v}_FILE"
    if [ -z "${!v:-}" ] && [ -n "${!f:-}" ]; then export "$v=$(cat "${!f}")"; fi
done
: "${DB_PASSWORD:?DB_PASSWORD (or DB_PASSWORD_FILE) is required}"

# Encryption keys: from the environment (as the martialblog image), else
# LimeSurvey generates them into security.php (in the volume) on first use.
if [ ! -s /var/limesurvey/security.php ] && { [ -n "${ENCRYPT_KEYPAIR:-}" ] || [ -n "${ENCRYPT_SECRET_BOX_KEY:-}" ]; }; then
    cat > /var/limesurvey/security.php <<EOF
<?php if (!defined('BASEPATH')) exit('No direct script access allowed');
\$config = array();
\$config['encryptionkeypair'] = '${ENCRYPT_KEYPAIR:-}';
\$config['encryptionpublickey'] = '${ENCRYPT_PUBLIC_KEY:-}';
\$config['encryptionsecretkey'] = '${ENCRYPT_SECRET_KEY:-}';
\$config['encryptionnonce'] = '${ENCRYPT_NONCE:-}';
\$config['encryptionsecretboxkey'] = '${ENCRYPT_SECRET_BOX_KEY:-}';
return \$config;
EOF
fi

echo "==> waiting for database at ${DB_HOST:-db}"
i=0
until ephpm php -r '
    $t = getenv("DB_TYPE") ?: "mysql";
    $dsn = "$t:host=" . (getenv("DB_HOST") ?: "db") . ";port=" . (getenv("DB_PORT") ?: ($t === "pgsql" ? 5432 : 3306)) . ";dbname=" . (getenv("DB_NAME") ?: "limesurvey");
    try { new PDO($dsn, getenv("DB_USERNAME") ?: "limesurvey", getenv("DB_PASSWORD")); } catch (Throwable $e) { exit(1); }
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

# Same detection as the martialblog image: updatedb fails on an empty database.
if ephpm php application/commands/console.php updatedb >/dev/null 2>&1; then
    echo "==> database already provisioned (updatedb ran)"
else
    echo "==> installing LimeSurvey (console.php install)"
    ephpm php application/commands/console.php install \
        "${ADMIN_USER:-admin}" "${ADMIN_PASSWORD:?ADMIN_PASSWORD (or ADMIN_PASSWORD_FILE) is required for the first start}" \
        "${ADMIN_NAME:-Administrator}" "${ADMIN_EMAIL:-admin@example.com}"
fi

exec ephpm serve --config "$CONFIG" "$@"
