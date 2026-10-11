#!/bin/sh
# First-run setup, then ePHPm in the foreground.
set -eu
cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
mkdir -p tmp/cache/models tmp/cache/persistent tmp/cache/views tmp/sessions tmp/tests logs

# SECURITY_SALT: from the environment, else generated once into tmp/ (a volume).
if [ -z "${SECURITY_SALT:-}" ]; then
    [ -f tmp/.security_salt ] || ephpm php -r 'echo bin2hex(random_bytes(32));' > tmp/.security_salt
    SECURITY_SALT="$(cat tmp/.security_salt)"
    export SECURITY_SALT
fi

host="$(printf '%s' "${DATABASE_URL:-}" | sed -nE 's#^[a-z]+://([^@]*@)?([^:/?]+).*#\2#p')"

migrate() {
    i=0
    until ephpm php bin/cake.php migrations status >/dev/null 2>&1; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; return 1; }
        sleep 2
    done
    echo "==> running migrations"
    ephpm php bin/cake.php migrations migrate --no-lock
}

if [ "${SKIP_MIGRATE:-0}" != "1" ]; then
    case "$host" in
        127.0.0.1|localhost|"") migrate & ;;   # embedded DB: reachable once the server runs
        *) migrate ;;
    esac
fi

exec ephpm serve --config "$CONFIG" "$@"
