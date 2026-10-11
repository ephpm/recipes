#!/bin/sh
# Container entrypoint: the official image's prepare-environment.sh on the
# embedded PHP — write /app/.env from the CP_* variables, wait for the
# database, `spark castopod:database-update`, `spark cache:clear` — then
# ePHPm in the foreground. With arguments (the `cron` service) it runs them
# after the setup instead.
set -eu

cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# writable/ and public/media live in volumes; seed them when created empty.
[ -n "$(ls -A writable 2>/dev/null)" ] || cp -a /usr/local/share/castopod/writable/. writable/
[ -n "$(ls -A public/media 2>/dev/null)" ] || cp -a /usr/local/share/castopod/media/. public/media/
mkdir -p writable/cache writable/logs writable/session writable/uploads writable/temp

log_error() { echo "!!! $1" >&2; exit 1; }

[ -n "${CP_BASEURL:-}" ] || log_error "CP_BASEURL must be set"
CP_MEDIA_BASEURL="${CP_MEDIA_BASEURL:-$CP_BASEURL}"
CP_ADMIN_GATEWAY="${CP_ADMIN_GATEWAY:-cp-admin}"
CP_AUTH_GATEWAY="${CP_AUTH_GATEWAY:-cp-auth}"
CP_DATABASE_HOSTNAME="${CP_DATABASE_HOSTNAME:-mariadb}"
CP_DATABASE_PREFIX="${CP_DATABASE_PREFIX:-cp_}"
CP_DATABASE_NAME="${CP_DATABASE_NAME:-${MYSQL_DATABASE:-}}"
CP_DATABASE_USERNAME="${CP_DATABASE_USERNAME:-${MYSQL_USER:-}}"
CP_DATABASE_PASSWORD="${CP_DATABASE_PASSWORD:-${MYSQL_PASSWORD:-}}"
[ -n "$CP_DATABASE_NAME" ] || log_error "CP_DATABASE_NAME (or MYSQL_DATABASE) must be set"
[ -n "$CP_DATABASE_USERNAME" ] || log_error "CP_DATABASE_USERNAME (or MYSQL_USER) must be set"

# The analytics salt must be stable (it hashes listener IPs). The official
# image requires CP_ANALYTICS_SALT; here it is generated once into the
# writable volume when unset.
if [ -z "${CP_ANALYTICS_SALT:-}" ]; then
    [ -s writable/.analytics-salt ] || ( umask 077 && ephpm php -r 'echo bin2hex(random_bytes(32));' > writable/.analytics-salt )
    CP_ANALYTICS_SALT="$(cat writable/.analytics-salt)"
fi

rm -f .env
{
    printf 'app.baseURL="%s"\nmedia.baseURL="%s"\n' "$CP_BASEURL" "$CP_MEDIA_BASEURL"
    if [ "${CP_DISABLE_HTTPS:-0}" = "1" ]; then
        echo "app.forceGlobalSecureRequests=false"
    fi
    printf 'admin.gateway="%s"\nauth.gateway="%s"\n\nanalytics.salt="%s"\n\n' "$CP_ADMIN_GATEWAY" "$CP_AUTH_GATEWAY" "$CP_ANALYTICS_SALT"
    printf 'database.default.hostname="%s"\ndatabase.default.database="%s"\ndatabase.default.username="%s"\ndatabase.default.password="%s"\ndatabase.default.DBPrefix="%s"\n' \
        "$CP_DATABASE_HOSTNAME" "$CP_DATABASE_NAME" "$CP_DATABASE_USERNAME" "$CP_DATABASE_PASSWORD" "$CP_DATABASE_PREFIX"
    [ -n "${CP_DATABASE_PORT:-}" ] && printf 'database.default.port=%s\n' "$CP_DATABASE_PORT"
    echo 'cache.handler="file"'
    [ "${CP_ENABLE_2FA:-}" = "true" ] && echo "auth.enable2FA=true"
    if [ -n "${CP_EMAIL_SMTP_HOST:-}" ]; then
        printf 'email.protocol="smtp"\nemail.SMTPHost="%s"\nemail.SMTPUser=%s\nemail.SMTPPass=%s\nemail.fromEmail=%s\n' \
            "$CP_EMAIL_SMTP_HOST" "${CP_EMAIL_SMTP_USERNAME:-}" "${CP_EMAIL_SMTP_PASSWORD:-}" "${CP_EMAIL_FROM:-}"
        [ -n "${CP_EMAIL_SMTP_PORT:-}" ] && printf 'email.SMTPPort=%s\n' "$CP_EMAIL_SMTP_PORT"
        [ -n "${CP_EMAIL_SMTP_CRYPTO:-}" ] && printf 'email.SMTPCrypto=%s\n' "$CP_EMAIL_SMTP_CRYPTO"
    fi
    true
} > .env
chmod 600 .env

echo "==> waiting for database at $CP_DATABASE_HOSTNAME:${CP_DATABASE_PORT:-3306}"
i=0
until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$CP_DATABASE_HOSTNAME" "${CP_DATABASE_PORT:-3306}" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 90 ] && log_error "database at $CP_DATABASE_HOSTNAME not reachable after 90 tries"
    sleep 2
done

# The cron service (arguments given) only needs .env and the database;
# migrations run once, in the web container.
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# Migrations + cache, as the official bootstrap does on every start.
spark castopod:database-update
spark cache:clear
echo "==> Castopod is ready"
exec ephpm serve --config "$CONFIG"
