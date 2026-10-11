#!/bin/bash
# Container entrypoint: the official joomla image's docker-entrypoint.sh with
# Apache taken out — copy the release into the volume on first start, wait
# for the database, auto-install with installation/joomla.php when the
# JOOMLA_SITE_NAME / JOOMLA_ADMIN_* variables are set (and remove
# installation/), optional extensions and SMTP, then ePHPm.
set -euo pipefail

WEB=/var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$WEB"

if [ -n "${JOOMLA_DB_PASSWORD_FILE:-}" ] && [ -f "$JOOMLA_DB_PASSWORD_FILE" ]; then
    JOOMLA_DB_PASSWORD="$(cat "$JOOMLA_DB_PASSWORD_FILE")"
fi
: "${JOOMLA_DB_HOST:?JOOMLA_DB_HOST is required (and JOOMLA_DB_USER / JOOMLA_DB_PASSWORD / JOOMLA_DB_NAME)}"
: "${JOOMLA_DB_USER:=root}" "${JOOMLA_DB_NAME:=joomla}" "${JOOMLA_DB_PASSWORD:=}" "${JOOMLA_DB_TYPE:=mysqli}"

# First start: copy the release into the (empty) volume.
if [ ! -e index.php ] && [ ! -e libraries/src/Version.php ]; then
    echo "==> copying Joomla into $WEB"
    cp -a /usr/src/joomla/. "$WEB/"
fi

echo "==> waiting for database at $JOOMLA_DB_HOST"
i=0
until ephpm php -r '
    [$h, $p] = array_pad(explode(":", $argv[1], 2), 2, null);
    $t = $argv[2];
    try {
        $dsn = ($t === "pgsql" ? "pgsql:host=$h" . ($p ? ";port=$p" : "") : "mysql:host=$h" . ($p ? ";port=$p" : "")) . ";dbname=" . $argv[3];
        new PDO($dsn, getenv("JOOMLA_DB_USER"), getenv("JOOMLA_DB_PASSWORD"));
    } catch (Throwable $e) { exit(1); }
' -- "$JOOMLA_DB_HOST" "$JOOMLA_DB_TYPE" "$JOOMLA_DB_NAME" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at $JOOMLA_DB_HOST not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

can_auto_deploy() {
    [ -n "${JOOMLA_SITE_NAME:-}" ] && [ -n "${JOOMLA_ADMIN_USER:-}" ] && [ -n "${JOOMLA_ADMIN_USERNAME:-}" ] \
        && [ -n "${JOOMLA_ADMIN_PASSWORD:-}" ] && [ -n "${JOOMLA_ADMIN_EMAIL:-}" ] || return 1
    # the official image's checks (Joomla's own installer enforces the rest)
    [ "${#JOOMLA_SITE_NAME}" -gt 2 ] || { echo "!!! JOOMLA_SITE_NAME must be longer than 2 characters" >&2; return 1; }
    [ "${#JOOMLA_ADMIN_USER}" -gt 2 ] || { echo "!!! JOOMLA_ADMIN_USER must be longer than 2 characters" >&2; return 1; }
    [[ ! "$JOOMLA_ADMIN_USERNAME" =~ [^a-zA-Z] ]] || { echo "!!! JOOMLA_ADMIN_USERNAME must be letters only" >&2; return 1; }
    [ "${#JOOMLA_ADMIN_PASSWORD}" -gt 12 ] || { echo "!!! JOOMLA_ADMIN_PASSWORD must be longer than 12 characters" >&2; return 1; }
}

if [ -d installation ] && [ -e installation/joomla.php ]; then
    if can_auto_deploy; then
        echo "==> installing Joomla (installation/joomla.php install)"
        ephpm php installation/joomla.php install \
            --site-name="$JOOMLA_SITE_NAME" --admin-email="$JOOMLA_ADMIN_EMAIL" \
            --admin-username="$JOOMLA_ADMIN_USERNAME" --admin-user="$JOOMLA_ADMIN_USER" \
            --admin-password="$JOOMLA_ADMIN_PASSWORD" \
            --db-type="$JOOMLA_DB_TYPE" --db-host="$JOOMLA_DB_HOST" --db-name="$JOOMLA_DB_NAME" \
            --db-user="$JOOMLA_DB_USER" --db-pass="$JOOMLA_DB_PASSWORD" \
            --db-prefix="${JOOMLA_DB_PREFIX:-joom_}" --db-encryption=0
        rm -rf installation
        echo "==> Joomla installed"

        IFS=';' read -ra urls <<< "${JOOMLA_EXTENSIONS_URLS:-}"
        for u in "${urls[@]}"; do
            [ -n "$u" ] && { ephpm php cli/joomla.php extension:install --url "$u" --no-interaction || echo "!!! failed to install $u" >&2; }
        done
        IFS=';' read -ra paths <<< "${JOOMLA_EXTENSIONS_PATHS:-}"
        for p in "${paths[@]}"; do
            [ -n "$p" ] && { ephpm php cli/joomla.php extension:install --path "$p" --no-interaction || echo "!!! failed to install $p" >&2; }
        done
        if [ -n "${JOOMLA_SMTP_HOST:-}" ]; then
            smtp_host="${JOOMLA_SMTP_HOST%%:*}"; smtp_port=""
            [[ "$JOOMLA_SMTP_HOST" == *:* ]] && smtp_port="${JOOMLA_SMTP_HOST##*:}"
            ephpm php cli/joomla.php config:set mailer=smtp smtphost="$smtp_host" ${smtp_port:+smtpport="$smtp_port"} --no-interaction
        fi
    else
        echo "==> JOOMLA_SITE_NAME / JOOMLA_ADMIN_* not set: finish the installation in the browser"
    fi
fi

exec ephpm serve --config "$CONFIG" "$@"
