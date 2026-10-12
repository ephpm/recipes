#!/bin/sh
# Write config.local.php from the environment, wait for the database, create
# the schema (PostfixAdmin's own upgrade routine) and the first superadmin.
set -eu
cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

php -r '
$e = static fn (string $k, string $d = ""): string => (string) (getenv($k) ?: $d);
$cfg = "<?php\n"
  . "\$CONF[\"configured\"] = true;\n"
  . "\$CONF[\"database_type\"] = \"mysqli\";\n"
  . "\$CONF[\"database_host\"] = " . var_export($e("POSTFIXADMIN_DB_HOST", "db"), true) . ";\n"
  . "\$CONF[\"database_user\"] = " . var_export($e("POSTFIXADMIN_DB_USER", "postfixadmin"), true) . ";\n"
  . "\$CONF[\"database_password\"] = " . var_export($e("POSTFIXADMIN_DB_PASSWORD"), true) . ";\n"
  . "\$CONF[\"database_name\"] = " . var_export($e("POSTFIXADMIN_DB_NAME", "postfixadmin"), true) . ";\n"
  . "\$CONF[\"setup_password\"] = " . var_export(password_hash($e("POSTFIXADMIN_SETUP_PASSWORD"), PASSWORD_DEFAULT), true) . ";\n"
  . "\$CONF[\"encrypt\"] = \"md5crypt\";\n"
  . "\$CONF[\"emailcheck_resolve_domain\"] = false;\n"
  . "\$CONF[\"smtp_server\"] = " . var_export($e("POSTFIXADMIN_SMTP_SERVER", "localhost"), true) . ";\n";
file_put_contents("/app/config.local.php", $cfg);
'

echo "==> waiting for database"
i=0
until php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    exit(@mysqli_connect(getenv("POSTFIXADMIN_DB_HOST") ?: "db", getenv("POSTFIXADMIN_DB_USER") ?: "postfixadmin", getenv("POSTFIXADMIN_DB_PASSWORD") ?: "", getenv("POSTFIXADMIN_DB_NAME") ?: "postfixadmin") ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! database not reachable" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*)
        echo "==> creating / upgrading the schema"
        php -r '$_SERVER["REQUEST_METHOD"]="GET"; chdir("/app/public"); require "upgrade.php";' >/tmp/upgrade.log 2>&1 || { cat /tmp/upgrade.log >&2; exit 1; }
        if [ -n "${POSTFIXADMIN_ADMIN_PASSWORD:-}" ]; then
            # Inserted directly (and emailcheck_resolve_domain is off): PostfixAdmin validates addresses with
            # dns_get_record(), which hangs on ePHPm (known limit).
            php -r '
                mysqli_report(MYSQLI_REPORT_OFF);
                $e = static fn (string $k, string $d = ""): string => (string) (getenv($k) ?: $d);
                $db = mysqli_connect($e("POSTFIXADMIN_DB_HOST", "db"), $e("POSTFIXADMIN_DB_USER", "postfixadmin"), $e("POSTFIXADMIN_DB_PASSWORD"), $e("POSTFIXADMIN_DB_NAME", "postfixadmin"));
                $u = $e("POSTFIXADMIN_ADMIN_EMAIL", "admin@example.org");
                $r = mysqli_query($db, "SELECT 1 FROM admin WHERE username=\"" . mysqli_real_escape_string($db, $u) . "\"");
                if ($r && mysqli_num_rows($r) > 0) { exit(0); }
                $h = crypt($e("POSTFIXADMIN_ADMIN_PASSWORD"), "\$1\$" . substr(bin2hex(random_bytes(4)), 0, 8) . "\$");
                $q = mysqli_real_escape_string($db, $u);
                mysqli_query($db, "INSERT INTO admin (username, password, created, modified, active, superadmin) VALUES (\"$q\", \"" . mysqli_real_escape_string($db, $h) . "\", NOW(), NOW(), 1, 1)");
                mysqli_query($db, "INSERT INTO domain_admins (username, domain, created, active) VALUES (\"$q\", \"ALL\", NOW(), 1)");
                echo "==> created superadmin $u\n";
            '
        fi
        exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
