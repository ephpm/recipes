#!/bin/sh
# Container entrypoint: first-run setup, then ePHPm in the foreground.
set -eu

HTML=/var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# wp-content lives in a volume; make sure the bits the image ships are there
# even when the volume was created empty (a bind mount, or a pre-created one).
for d in plugins themes cache-wordpress index.php; do
    [ -e "$HTML/wp-content/$d" ] || cp -a "/usr/local/share/wordpress/wp-content/$d" "$HTML/wp-content/"
done
[ -f "$HTML/wp-content/object-cache.php" ] || printf '<?php\nrequire __DIR__ . "/cache-wordpress/dropin/object-cache.php";\n' > "$HTML/wp-content/object-cache.php"
mkdir -p "$HTML/wp-content/uploads"

# Generate salts once (persisted in the wp-content volume) unless provided.
if [ -z "${WORDPRESS_AUTH_KEY:-}" ] && [ ! -f "$HTML/wp-content/ephpm-salts.php" ]; then
    ephpm php -r '
        $out = "<?php\nreturn [\n";
        foreach (["AUTH_KEY","SECURE_AUTH_KEY","LOGGED_IN_KEY","NONCE_KEY","AUTH_SALT","SECURE_AUTH_SALT","LOGGED_IN_SALT","NONCE_SALT"] as $k) {
            $out .= sprintf("    %s => %s,\n", var_export($k, true), var_export(bin2hex(random_bytes(32)), true));
        }
        file_put_contents($argv[1], $out . "];\n");
    ' "$HTML/wp-content/ephpm-salts.php"
fi

# Wait for an external database (the embedded one starts with the server).
DB_HOST="${WORDPRESS_DB_HOST:-127.0.0.1:3306}"
case "$DB_HOST" in
    127.0.0.1*|localhost*) ;;
    *)
        echo "==> waiting for database at $DB_HOST"
        i=0
        until ephpm php -r '
            [$h, $p] = array_pad(explode(":", $argv[1], 2), 2, 3306);
            mysqli_report(MYSQLI_REPORT_OFF);
            $c = @mysqli_connect($h, getenv("WORDPRESS_DB_USER") ?: "root", getenv("WORDPRESS_DB_PASSWORD") ?: "", getenv("WORDPRESS_DB_NAME") ?: "wordpress", (int) $p);
            exit($c ? 0 : 1);
        ' "$DB_HOST" 2>/dev/null; do
            i=$((i + 1))
            [ "$i" -ge 60 ] && { echo "!!! database at $DB_HOST not reachable after 60 tries" >&2; exit 1; }
            sleep 2
        done
        ;;
esac

exec ephpm serve --config "$CONFIG" "$@"
