#!/bin/sh
# Container entrypoint: the official partdb-entrypoint.sh's steps on the
# embedded PHP — seed the volumes, resolve APP_SECRET, wait for the
# database, migrate (DB_AUTOMIGRATE, on by default here), optionally set the
# admin password, then ePHPm in the foreground.
set -eu

cd /var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# uploads/ and public/media live in volumes; seed them when created empty.
[ -n "$(ls -A uploads 2>/dev/null)" ] || cp -a /usr/local/share/partdb/uploads/. uploads/
[ -n "$(ls -A public/media 2>/dev/null)" ] || cp -a /usr/local/share/partdb/media/. public/media/
mkdir -p var/cache var/log var/db uploads/.automigration-backup

# APP_SECRET: the environment wins (the official image requires it);
# otherwise generate one once and keep it in the var/db volume.
if [ -z "${APP_SECRET:-}" ] || [ "$APP_SECRET" = "CHANGE_ME" ]; then
    if [ ! -s var/db/.appsecret ]; then
        ( umask 077 && ephpm php -r 'echo bin2hex(random_bytes(32));' > var/db/.appsecret )
        echo "==> APP_SECRET: generated and persisted to var/db/.appsecret"
    fi
    APP_SECRET="$(cat var/db/.appsecret)"
    export APP_SECRET
fi

export DATABASE_URL="${DATABASE_URL:-sqlite:///%kernel.project_dir%/var/db/app.db}"
export APP_ENV="${APP_ENV:-docker}"

DB_HOST="$(ephpm php -r 'echo parse_url($argv[1], PHP_URL_HOST) ?: "";' "$DATABASE_URL")"
DB_PORT="$(ephpm php -r 'echo parse_url($argv[1], PHP_URL_PORT) ?: (str_starts_with($argv[1], "postgres") ? 5432 : 3306);' "$DATABASE_URL")"

wait_db() {
    echo "==> waiting for database at $DB_HOST:$DB_PORT"
    i=0
    until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$DB_HOST" "$DB_PORT" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 90 ] && { echo "!!! database at $DB_HOST:$DB_PORT not reachable after 90 tries" >&2; exit 1; }
        sleep 2
    done
}

migrate() {
    rm -rf var/cache/*
    if [ "${DB_AUTOMIGRATE:-true}" = "true" ]; then
        if partdb doctrine:migrations:up-to-date --no-interaction >/dev/null 2>&1; then
            echo "==> database is up to date"
        else
            echo "==> running migrations (a fresh database prints the initial admin password below)"
            partdb doctrine:migrations:migrate --no-interaction
        fi
    fi
    # Optional: pin the admin password from the environment (first start or
    # any later start — it is idempotent). Otherwise use the one the first
    # migration printed, or run `partdb partdb:users:set-password admin`.
    if [ -n "${ADMIN_PASSWORD:-}" ]; then
        # answers: "continue as root? [no]", "proceed? [yes]", the password, its confirmation.
        # SHELL_INTERACTIVE=1: Symfony Console treats a non-tty stdin as
        # non-interactive and would skip the questions otherwise.
        if printf 'y\nyes\n%s\n%s\n' "$ADMIN_PASSWORD" "$ADMIN_PASSWORD" | SHELL_INTERACTIVE=1 partdb partdb:users:set-password admin >/dev/null; then
            echo "==> admin password set from ADMIN_PASSWORD"
            # The first migration flags admin for a forced password change; the
            # operator just chose the password, so clear it (set-password does not).
            # ("y" answers Part-DB's "running as root, continue? [no]" prompt)
            printf 'y\n' | SHELL_INTERACTIVE=1 partdb dbal:run-sql "UPDATE users SET need_pw_change = 0 WHERE name = 'admin'" >/dev/null
        else
            echo "!!! setting the admin password from ADMIN_PASSWORD failed" >&2
        fi
    fi
    partdb cache:warmup --no-interaction >/dev/null
    echo "==> Part-DB is ready"
}

case "$DB_HOST" in
    "")                       migrate ;;                       # SQLite file
    127.0.0.1|localhost)      ( wait_db; migrate ) & ;;         # embedded listener starts with the server
    *)                        wait_db; migrate ;;
esac

exec ephpm serve --config "$CONFIG" "$@"
