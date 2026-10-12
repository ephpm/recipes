#!/bin/sh
# Container entrypoint — the official dolibarr/dolibarr image's docker-run.sh
# on the embedded PHP: write conf/conf.php from the DOLI_* variables, load
# the schema + default data + super admin into an empty database
# (DOLI_INSTALL_AUTO=1), enable the base modules, lock the installer, then
# ePHPm in the foreground. With arguments (the cron service) it waits for
# the lock and runs them instead.
set -eu

HTDOCS=/var/www/dolibarr/htdocs
DOCS=/var/www/documents
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$HTDOCS"

: "${DOLI_DB_HOST:=db}"
: "${DOLI_DB_HOST_PORT:=3306}"
: "${DOLI_DB_NAME:=dolibarr}"
: "${DOLI_DB_USER:=dolibarr}"
: "${DOLI_DB_PASSWORD:=}"
: "${DOLI_URL_ROOT:=http://localhost:8080}"
: "${DOLI_ADMIN_LOGIN:=admin}"
export DOLI_DB_HOST DOLI_DB_HOST_PORT DOLI_DB_NAME DOLI_DB_USER DOLI_DB_PASSWORD DOLI_ADMIN_LOGIN

mkdir -p "$DOCS"
# The instance unique id (Dolibarr derives encryption keys from it) must be
# stable across container recreation: keep it with the documents.
if [ -z "${DOLI_INSTANCE_UNIQUE_ID:-}" ]; then
    [ -f "$DOCS/.ephpm-instance-id" ] || ephpm php -r 'echo bin2hex(random_bytes(16));' > "$DOCS/.ephpm-instance-id"
    DOLI_INSTANCE_UNIQUE_ID="$(cat "$DOCS/.ephpm-instance-id")"
fi
# The key the cron service authenticates scheduled-job runs with (written
# into Dolibarr's CRON_KEY at install time, read by the cron service).
if [ -n "${DOLI_CRON_KEY:-}" ]; then
    printf '%s' "$DOLI_CRON_KEY" > "$DOCS/.ephpm-cron-key"
elif [ ! -f "$DOCS/.ephpm-cron-key" ]; then
    ephpm php -r 'echo bin2hex(random_bytes(16));' > "$DOCS/.ephpm-cron-key"
fi
DOLI_CRON_KEY="$(cat "$DOCS/.ephpm-cron-key")"
export DOLI_CRON_KEY

# conf/conf.php from the environment, as the official image writes it
# (lives in the container; rewritten on each new container).
if [ ! -f conf/conf.php ]; then
    php_str() { printf '%s' "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g"; }
    cat > conf/conf.php <<EOF
<?php
\$dolibarr_main_url_root='$(php_str "$DOLI_URL_ROOT")';
\$dolibarr_main_document_root='$HTDOCS';
\$dolibarr_main_url_root_alt='/custom';
\$dolibarr_main_document_root_alt='$HTDOCS/custom';
\$dolibarr_main_data_root='$DOCS';
\$dolibarr_main_db_host='$(php_str "$DOLI_DB_HOST")';
\$dolibarr_main_db_port='$DOLI_DB_HOST_PORT';
\$dolibarr_main_db_name='$(php_str "$DOLI_DB_NAME")';
\$dolibarr_main_db_prefix='llx_';
\$dolibarr_main_db_user='$(php_str "$DOLI_DB_USER")';
\$dolibarr_main_db_pass='$(php_str "$DOLI_DB_PASSWORD")';
\$dolibarr_main_db_type='mysqli';
\$dolibarr_main_db_character_set='utf8mb4';
\$dolibarr_main_db_collation='utf8mb4_unicode_ci';
\$dolibarr_main_authentication='${DOLI_AUTH:-dolibarr}';
\$dolibarr_main_prod=${DOLI_PROD:-1};
\$dolibarr_main_instance_unique_id='$DOLI_INSTANCE_UNIQUE_ID';
EOF
    chmod 400 conf/conf.php
fi

echo "==> waiting for database at $DOLI_DB_HOST:$DOLI_DB_HOST_PORT"
i=0
until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$DOLI_DB_HOST" "$DOLI_DB_HOST_PORT" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 90 ] && { echo "!!! database at $DOLI_DB_HOST not reachable after 90 tries" >&2; exit 1; }
    sleep 2
done

if [ "$#" -gt 0 ]; then
    until [ -f "$DOCS/install.lock" ]; do echo "==> waiting for the web container to install Dolibarr"; sleep 5; done
    exec "$@"
fi

has_schema() {
    ephpm php -r '
        mysqli_report(MYSQLI_REPORT_OFF);
        $c = @mysqli_connect(getenv("DOLI_DB_HOST"), getenv("DOLI_DB_USER"), getenv("DOLI_DB_PASSWORD"), getenv("DOLI_DB_NAME"), (int) getenv("DOLI_DB_HOST_PORT"));
        $r = $c ? mysqli_query($c, "SHOW TABLES LIKE \x27llx_const\x27") : false;
        exit($r && mysqli_num_rows($r) > 0 ? 0 : 1);
    '
}

if [ ! -f "$DOCS/install.lock" ] && [ "${DOLI_INSTALL_AUTO:-1}" = "1" ]; then
    if has_schema; then
        echo "==> database already holds a Dolibarr schema"
    else
        [ -n "${DOLI_ADMIN_PASSWORD:-}" ] || { echo "!!! DOLI_ADMIN_PASSWORD must be set for the first start" >&2; exit 1; }
        export DOLI_ADMIN_PASSWORD
        echo "==> loading the schema, default data and the super admin"
        ephpm php /var/www/dolibarr/ephpm/init-db.php "$HTDOCS"
        echo "==> enabling the base modules"
        ephpm php -d memory_limit=-1 /var/www/dolibarr/ephpm/init-modules.php
    fi
    touch "$DOCS/install.lock"
    chmod 400 "$DOCS/install.lock"
fi
echo "==> Dolibarr is ready"

exec ephpm serve --config "$CONFIG"
