#!/bin/sh
# Container entrypoint: the official docker/entrypoint.sh's steps on the
# embedded PHP — write .env.local from the environment, migrate, refresh
# cached values, generate the JWT key pair — then ePHPm in the foreground.
set -eu

cd /app/public
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
STATE=/var/lib/koillection          # secrets + JWT keys (a volume, never web-served)

# public/uploads lives in a volume; seed it when it was created empty.
[ -n "$(ls -A public/uploads 2>/dev/null)" ] || cp -a /usr/local/share/koillection-uploads/. public/uploads/
mkdir -p "$STATE/jwt" var/cache var/log var/share

# Secrets: the environment wins; otherwise generate once into the state volume
# (the official image regenerates them on every start, which invalidates
# remember-me cookies and API tokens — persisted here instead).
secret() {   # secret NAME FILE
    eval "v=\${$1:-}"
    if [ -z "$v" ]; then
        [ -s "$STATE/$2" ] || ( umask 077 && ephpm php -r 'echo bin2hex(random_bytes(24));' > "$STATE/$2" )
        v="$(cat "$STATE/$2")"
    fi
    printf '%s' "$v"
}
APP_SECRET="$(secret APP_SECRET app_secret)"
JWT_PASSPHRASE="$(secret JWT_PASSPHRASE jwt_passphrase)"

cat > .env.local <<EOF
APP_ENV=${APP_ENV:-prod}
APP_DEBUG=${APP_DEBUG:-0}
APP_SECRET=$APP_SECRET
JWT_SECRET_KEY=${JWT_SECRET_KEY:-$STATE/jwt/private.pem}
JWT_PUBLIC_KEY=${JWT_PUBLIC_KEY:-$STATE/jwt/public.pem}
JWT_PASSPHRASE=$JWT_PASSPHRASE
DB_DRIVER=${DB_DRIVER:-pdo_pgsql}
DB_NAME=${DB_NAME:-koillection}
DB_HOST=${DB_HOST:-db}
DB_PORT=${DB_PORT:-5432}
DB_USER=${DB_USER:-koillection}
DB_PASSWORD=${DB_PASSWORD:-koillection}
DB_VERSION=${DB_VERSION:-16}
CORS_ALLOW_ORIGIN=${CORS_ALLOW_ORIGIN:-'^https?://(localhost|127\.0\.0\.1)(:[0-9]+)?$'}
EOF
chmod 600 .env.local

# The same variables must not also sit in the process environment with
# different values: Symfony's Dotenv never overrides a real env var.
export APP_SECRET JWT_PASSPHRASE

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"

wait_db() {
    echo "==> waiting for database at $DB_HOST:$DB_PORT"
    i=0
    until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$DB_HOST" "$DB_PORT" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 90 ] && { echo "!!! database at $DB_HOST:$DB_PORT not reachable after 90 tries" >&2; exit 1; }
        sleep 2
    done
}

setup() {
    rm -rf var/cache/*
    koillection doctrine:migration:migrate --no-interaction --allow-no-migration
    koillection app:refresh-cached-values
    koillection lexik:jwt:generate-keypair --skip-if-exists --no-interaction
    koillection cache:warmup --no-interaction >/dev/null
    echo "==> Koillection is ready"
}

case "$DB_HOST" in
    127.0.0.1|localhost) ( wait_db; setup ) & ;;   # embedded listener starts with the server
    *)                   wait_db; setup ;;
esac

exec ephpm serve --config "$CONFIG" "$@"
