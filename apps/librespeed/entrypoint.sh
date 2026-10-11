#!/bin/bash
# Container entrypoint: the official image's docker/entrypoint.sh, with
# Apache replaced by ePHPm. Assembles /var/www/html from /speedtest according
# to the same variables (MODE, TELEMETRY, DB_TYPE, PASSWORD, TITLE, ...),
# creates the telemetry table on MySQL/PostgreSQL (the official image leaves
# that to you), then starts ePHPm in the foreground.
set -euo pipefail

SRC=/speedtest
WEB=/var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
: "${MODE:=standalone}" "${TELEMETRY:=false}" "${DB_TYPE:=sqlite}" "${USE_NEW_DESIGN:=false}"
: "${TITLE:=}" "${TAGLINE:=}" "${GDPR_EMAIL:=${EMAIL:-}}" "${SERVER_LIST_URL:=}" "${IPINFO_APIKEY:=}"
echo "==> LibreSpeed MODE=$MODE TELEMETRY=$TELEMETRY DB_TYPE=$DB_TYPE"

html_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"; }
sed_escape() { printf '%s\n' "$1" | sed 's/[&/\\]/\\&/g; s/\$/\\$/g'; }

# The web root is rebuilt from the image at every start (as upstream does).
rm -rf "${WEB:?}"/* "${WEB:?}"/.[!.]* 2>/dev/null || true
cp "$SRC"/*.js "$SRC/config.json" "$SRC/favicon.ico" "$SRC/manifest.webmanifest" "$SRC/stability.html" "$WEB/"
cp -r "$SRC/images" "$WEB/"

case "$MODE" in
    standalone|dual) cp -r "$SRC/backend" "$WEB/backend" ;;
    backend) cp -r "$SRC/backend/." "$WEB/" ;;
    frontend) ;;
    *) echo "!!! unknown MODE '$MODE' (standalone | backend | frontend | dual)" >&2; exit 1 ;;
esac
if [ -n "$IPINFO_APIKEY" ]; then
    for f in "$WEB/backend/getIP_ipInfo_apikey.php" "$WEB/getIP_ipInfo_apikey.php"; do
        if [ -f "$f" ]; then sed -i "s/\$IPINFO_APIKEY = ''/\$IPINFO_APIKEY = '$(sed_escape "$IPINFO_APIKEY")'/" "$f"; fi
    done
fi
if [[ "$MODE" == frontend || "$MODE" == dual ]] && [ -f /servers.json ]; then cp /servers.json "$WEB/servers.json"; fi

if [[ "$MODE" != backend ]]; then
    cp "$SRC/index.html" "$SRC/index-classic.html" "$SRC/index-modern.html" "$WEB/"
    cp -a "$SRC/frontend" "$WEB/"
    cp "$SRC/settings.json" "$WEB/settings.json"
    if [ -f /servers.json ]; then
        cp /servers.json "$WEB/server-list.json"
    elif [ -z "$SERVER_LIST_URL" ]; then
        [ "$MODE" == frontend ] && { echo "!!! MODE=frontend needs /servers.json or SERVER_LIST_URL" >&2; exit 1; }
        echo '[{"name":"local","server":"/backend","dlURL":"garbage.php","ulURL":"empty.php","pingURL":"empty.php","getIpURL":"getIP.php","sponsorName":"","sponsorURL":"","id":1}]' > "$WEB/server-list.json"
    fi
    if [ -n "$SERVER_LIST_URL" ]; then
        u="$(sed_escape "$SERVER_LIST_URL")"
        sed -i "s/var SPEEDTEST_SERVERS = \"server-list.json\";/var SPEEDTEST_SERVERS = \"$u\";/" "$WEB/index-modern.html" "$WEB/stability.html"
        sed -i "/var SPEEDTEST_SERVERS = \\[/,/^[[:space:]]*];/c\\\t\tvar SPEEDTEST_SERVERS = \"$u\";" "$WEB/index-classic.html"
    fi
    if [ -f "$WEB/server-list.json" ]; then cp "$WEB/server-list.json" "$WEB/servers.json"; fi
    if [ -n "$TITLE" ]; then
        t="$(sed_escape "$(html_escape "${TITLE//$'\n'/ }")")"
        sed -i "s/<title>LibreSpeed<\\/title>/<title>$t<\\/title>/g; s/<h1>LibreSpeed<\\/h1>/<h1>$t<\\/h1>/g" "$WEB/index-classic.html"
        sed -i "s/<title>LibreSpeed<\\/title>/<title>$t<\\/title>/g" "$WEB/index.html"
        sed -i "s/<title>LibreSpeed - Free and Open Source Speedtest<\\/title>/<title>$t - Free and Open Source Speedtest<\\/title>/g; s/<h1>Free and Open Source Speedtest\\.<\\/h1>/<h1>$t<\\/h1>/g" "$WEB/index-modern.html"
    fi
    if [ -n "$TAGLINE" ]; then
        t="$(sed_escape "$(html_escape "${TAGLINE//$'\n'/ }")")"
        sed -i "s/<p class=\"tagline\">No Flash, No Java, No Websockets, No Bullsh\\*t<\\/p>/<p class=\"tagline\">$t<\\/p>/g" "$WEB/index-modern.html"
    fi
    if [ -n "$GDPR_EMAIL" ]; then
        e="$(sed_escape "$GDPR_EMAIL")"
        sed -i "s/TO BE FILLED BY DEVELOPER/$e/g; s/PUT@YOUR_EMAIL.HERE/$e/g" "$WEB/index-modern.html" "$WEB/index-classic.html"
    fi
fi
# ePHPm (per-request mode) buffers a PHP response completely before sending
# it — flush() does not stream (issues/librespeed.md). garbage.php writes
# ckSize MiB of random data per request, so: have the browsers ask for
# smaller chunks (DL_CHUNK_MB, default 10; upstream's client default is 100),
# and cap what one request can make the server buffer (GARBAGE_MAX_MB,
# default 32; upstream allows 1024).
: "${DL_CHUNK_MB:=10}" "${GARBAGE_MAX_MB:=32}"
[[ "$DL_CHUNK_MB" =~ ^[0-9]+$ && "$GARBAGE_MAX_MB" =~ ^[0-9]+$ ]] || { echo "!!! DL_CHUNK_MB / GARBAGE_MAX_MB must be integers" >&2; exit 1; }
for f in "$WEB/backend/garbage.php" "$WEB/garbage.php"; do
    if [ -f "$f" ]; then sed -i "s/> 1024) {/> $GARBAGE_MAX_MB) {/; s/return 1024;/return $GARBAGE_MAX_MB;/" "$f"; fi
done
if [ -f "$WEB/settings.json" ]; then
    sed -i "s/^{/{\n  \"garbagePhp_chunkSize\": $DL_CHUNK_MB,/" "$WEB/settings.json"
    sed -i "s/var s = new Speedtest(); \/\/create speed test object/&\n\t\ts.setParameter(\"garbagePhp_chunkSize\", $DL_CHUNK_MB);/" "$WEB/index-classic.html"
fi

if [ "$USE_NEW_DESIGN" == true ]; then sed -i 's/"useNewDesign": false/"useNewDesign": true/' "$WEB/config.json"; fi

# Telemetry: results/ with a settings file that reads the environment
# (upstream sed-patches the values in; reading them at runtime is equivalent
# and survives special characters in passwords).
if [[ "$TELEMETRY" == true && "$MODE" != backend ]]; then
    cp -r "$SRC/results" "$WEB/results"
    sed -i 's/telemetry_level": ".*"/telemetry_level": "basic"/' "$WEB/settings.json"
    if [ "$MODE" == frontend ]; then
        mkdir -p "$WEB/backend" && cp "$SRC/backend/getIP_util.php" "$WEB/backend/"
    fi
    case "$DB_TYPE" in mysql|postgresql|sqlite) ;; *) echo "!!! DB_TYPE must be mysql, postgresql or sqlite" >&2; exit 1 ;; esac
    cat > "$WEB/results/telemetry_settings.php" <<'EOF'
<?php
// Generated by entrypoint.sh: the official image's settings, read from the environment.
$db_type = getenv('DB_TYPE') ?: 'sqlite';
$stats_password = getenv('PASSWORD') ?: 'PASSWORD';      // 'PASSWORD' disables stats.php
$enable_id_obfuscation = getenv('ENABLE_ID_OBFUSCATION') === 'true';
$redact_ip_addresses = getenv('REDACT_IP_ADDRESSES') === 'true';
$Sqlite_db_file = '/database/db.sql';                    // the volume, outside the web root
$MySql_username = getenv('DB_USERNAME') ?: '';
$MySql_password = getenv('DB_PASSWORD') ?: '';
$MySql_hostname = getenv('DB_HOSTNAME') ?: 'db';
$MySql_databasename = getenv('DB_NAME') ?: 'speedtest';
$MySql_port = getenv('DB_PORT') ?: '3306';
$PostgreSql_username = $MySql_username;
$PostgreSql_password = $MySql_password;
$PostgreSql_hostname = $MySql_hostname;
$PostgreSql_databasename = $MySql_databasename;
EOF
    if [ "${ENABLE_ID_OBFUSCATION:-false}" == true ] && [ -n "${OBFUSCATION_SALT:-}" ]; then
        if [[ "$OBFUSCATION_SALT" =~ ^0x[0-9a-fA-F]+$ ]]; then
            printf '<?php\n$OBFUSCATION_SALT = %s;\n' "$OBFUSCATION_SALT" > "$WEB/results/idObfuscation_salt.php"
        else
            echo "WARNING: invalid OBFUSCATION_SALT (want a hex string like 0x1234abcd); using a random salt" >&2
        fi
    fi
    # A random salt, if one is generated, must survive restarts: keep it in the volume.
    if [ ! -f "$WEB/results/idObfuscation_salt.php" ]; then
        [ -f /database/idObfuscation_salt.php ] || \
            printf '<?php\n$OBFUSCATION_SALT = 0x%s;\n' "$(ephpm php -r 'echo bin2hex(random_bytes(4));')" > /database/idObfuscation_salt.php
        ln -sf /database/idObfuscation_salt.php "$WEB/results/idObfuscation_salt.php"
    fi

    # MySQL / PostgreSQL: wait for the server and create the table (upstream
    # ships results/telemetry_*.sql for you to load by hand).
    if [ "$DB_TYPE" != sqlite ]; then
        echo "==> waiting for $DB_TYPE at ${DB_HOSTNAME:-db}"
        i=0
        until ephpm php -r '
            $t = getenv("DB_TYPE"); $h = getenv("DB_HOSTNAME") ?: "db"; $n = getenv("DB_NAME") ?: "speedtest";
            $dsn = $t === "mysql" ? "mysql:host=$h;port=" . (getenv("DB_PORT") ?: 3306) . ";dbname=$n" : "pgsql:host=$h;dbname=$n";
            try { $pdo = new PDO($dsn, getenv("DB_USERNAME") ?: "", getenv("DB_PASSWORD") ?: "", [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]); }
            catch (Throwable $e) { exit(1); }
            $cols = "ip text NOT NULL, ispinfo text, extra text, ua text NOT NULL, lang text NOT NULL, dl text, ul text, ping text, jitter text";
            $pdo->exec($t === "mysql"
                ? "CREATE TABLE IF NOT EXISTS speedtest_users (id int NOT NULL AUTO_INCREMENT PRIMARY KEY, timestamp timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, $cols, log longtext) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
                : "CREATE TABLE IF NOT EXISTS speedtest_users (id serial PRIMARY KEY, \"timestamp\" timestamp NOT NULL DEFAULT now(), $cols, log text)");
        ' 2>/dev/null; do
            i=$((i + 1))
            [ "$i" -ge 60 ] && { echo "!!! $DB_TYPE at ${DB_HOSTNAME:-db} not reachable after 60 tries" >&2; exit 1; }
            sleep 2
        done
        echo "==> telemetry table ready"
    fi
fi

exec ephpm serve --config "$CONFIG" "$@"
