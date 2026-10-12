#!/bin/sh
# Write config.php from the environment, wait for the database, import the
# schema on the first start (phpIPAM's installer is a web wizard; this does
# what its "automatic database install" does), set the Admin password.
set -eu
cd /var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

php -r '
$e = static fn (string $k, string $d = ""): string => (string) (getenv($k) ?: $d);
$c = file_get_contents("/var/www/html/config.dist.php")
   . "\n// --- written by the ePHPm recipe entrypoint ---\n"
   . "\$disable_installer = true;\n"
   . "\$db[\"host\"] = " . var_export($e("IPAM_DATABASE_HOST", "db"), true) . ";\n"
   . "\$db[\"user\"] = " . var_export($e("IPAM_DATABASE_USER", "phpipam"), true) . ";\n"
   . "\$db[\"pass\"] = " . var_export($e("IPAM_DATABASE_PASS"), true) . ";\n"
   . "\$db[\"name\"] = " . var_export($e("IPAM_DATABASE_NAME", "phpipam"), true) . ";\n";
file_put_contents("/var/www/html/config.php", $c);
'

echo "==> waiting for database"
i=0
until php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    exit(@mysqli_connect(getenv("IPAM_DATABASE_HOST") ?: "db", getenv("IPAM_DATABASE_USER") ?: "phpipam", getenv("IPAM_DATABASE_PASS") ?: "", getenv("IPAM_DATABASE_NAME") ?: "phpipam") ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! database not reachable" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*)
        php -r '
            mysqli_report(MYSQLI_REPORT_OFF);
            $e = static fn (string $k, string $d = ""): string => (string) (getenv($k) ?: $d);
            $db = mysqli_connect($e("IPAM_DATABASE_HOST", "db"), $e("IPAM_DATABASE_USER", "phpipam"), $e("IPAM_DATABASE_PASS"), $e("IPAM_DATABASE_NAME", "phpipam"));
            $r = mysqli_query($db, "SHOW TABLES LIKE \"users\"");
            if ($r && mysqli_num_rows($r) > 0) { echo "==> schema present\n"; exit(0); }
            echo "==> importing db/SCHEMA.sql\n";
            if (!mysqli_multi_query($db, file_get_contents("/var/www/html/db/SCHEMA.sql"))) { fwrite(STDERR, mysqli_error($db) . "\n"); exit(1); }
            do { if ($res = mysqli_store_result($db)) { mysqli_free_result($res); } } while (mysqli_more_results($db) && mysqli_next_result($db));
            if (mysqli_errno($db)) { fwrite(STDERR, "schema import: " . mysqli_error($db) . "\n"); exit(1); }
            $p = $e("IPAM_ADMIN_PASSWORD");
            if ($p !== "") {
                $h = password_hash($p, PASSWORD_BCRYPT);
                mysqli_query($db, "UPDATE users SET password=\"" . mysqli_real_escape_string($db, $h) . "\", passChange=\"No\" WHERE username=\"Admin\"");
                echo "==> Admin password set\n";
            }
        '
        exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
