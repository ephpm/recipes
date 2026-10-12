#!/bin/sh
# First start: run MODX's CLI installer (setup/index.php --installmode=new)
# from the environment. core/ (config, cache, packages) is a volume; the four
# tiny config.core.php pointers outside it are regenerated when missing.
set -eu
cd /var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

[ -e core/model ] || cp -a /usr/local/share/modx-core/. core/

echo "==> waiting for database"
i=0
until php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    exit(@mysqli_connect(getenv("MODX_DB_HOST") ?: "db", getenv("MODX_DB_USER") ?: "modx", getenv("MODX_DB_PASSWORD") ?: "", getenv("MODX_DB_NAME") ?: "modx") ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! database not reachable" >&2; exit 1; }
    sleep 2
done

pointer() { # dir
    printf '<?php\n  define("MODX_CORE_PATH", "/var/www/html/core/");\n  define("MODX_CONFIG_KEY", "config");\n' > "$1/config.core.php"
}

if [ ! -f core/config/config.inc.php ]; then
    echo "==> installing MODX"
    cat > /tmp/modx-install.xml <<XML
<modx>
  <inplace>1</inplace>
  <unpacked>0</unpacked>
  <language>en</language>
  <database_type>mysql</database_type>
  <database_server>${MODX_DB_HOST:-db}</database_server>
  <database>${MODX_DB_NAME:-modx}</database>
  <database_user>${MODX_DB_USER:-modx}</database_user>
  <database_password>${MODX_DB_PASSWORD}</database_password>
  <database_connection_charset>utf8mb4</database_connection_charset>
  <database_charset>utf8mb4</database_charset>
  <database_collation>utf8mb4_general_ci</database_collation>
  <table_prefix>modx_</table_prefix>
  <https_port>443</https_port>
  <http_host>${MODX_HTTP_HOST:-localhost:8080}</http_host>
  <cache_disabled>0</cache_disabled>
  <cmsadmin>${MODX_ADMIN_USER:-admin}</cmsadmin>
  <cmspassword>${MODX_ADMIN_PASSWORD}</cmspassword>
  <cmsadminemail>${MODX_ADMIN_EMAIL:-admin@example.org}</cmsadminemail>
  <core_path>/var/www/html/core/</core_path>
  <context_mgr_path>/var/www/html/manager/</context_mgr_path>
  <context_mgr_url>/manager/</context_mgr_url>
  <context_connectors_path>/var/www/html/connectors/</context_connectors_path>
  <context_connectors_url>/connectors/</context_connectors_url>
  <context_web_path>/var/www/html/</context_web_path>
  <context_web_url>/</context_web_url>
  <remove_setup_directory>0</remove_setup_directory>
</modx>
XML
    php setup/index.php --installmode=new --config=/tmp/modx-install.xml > /tmp/install.log 2>&1 || true
    [ -f core/config/config.inc.php ] || { echo "!!! MODX installer failed:" >&2; tail -30 /tmp/install.log >&2; exit 1; }
    echo "==> MODX installed"
fi
for d in . manager connectors; do [ -f "$d/config.core.php" ] || pointer "$d"; done

case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
