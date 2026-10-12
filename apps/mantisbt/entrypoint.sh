#!/bin/sh
# Container entrypoint: seed the config volume, wait for the database, run
# MantisBT's installer unattended on the first start, apply schema upgrades
# on later starts, then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

APP=/app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$APP"
[ -n "$(ls -A config 2>/dev/null)" ] || cp -a /usr/local/share/mantisbt/config/. config/

echo "==> waiting for database at ${MANTIS_DB_HOST:-db}"
i=0
until php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    exit(@mysqli_connect(getenv("MANTIS_DB_HOST") ?: "db", getenv("MANTIS_DB_USER") ?: "mantis", getenv("MANTIS_DB_PASSWORD") ?: "", getenv("MANTIS_DB_NAME") ?: "bugtracker") ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

if [ ! -f config/config_inc.php ]; then
    # MantisBT's installer is the web page admin/install.php; a single POST
    # with install=2 runs every step (checks, schema, config_inc.php). Serve
    # it on a private loopback port for that one request — with /admin/
    # reachable, which the real configuration blocks.
    echo "==> installing MantisBT (admin/install.php)"
    sed 's|"/admin/\*", ||' "$CONFIG" > /tmp/install.toml
    ephpm serve --config /tmp/install.toml --listen 127.0.0.1:8099 >/tmp/install-server.log 2>&1 &
    srv=$!
    i=0
    until php -r 'exit(@file_get_contents("http://127.0.0.1:8099/admin/install.php") === false ? 1 : 0);' 2>/dev/null; do
        i=$((i + 1)); [ "$i" -ge 30 ] && { echo "!!! installer server did not start" >&2; cat /tmp/install-server.log >&2; exit 1; }
        sleep 1
    done
    php -r '
        $e = static fn (string $k, string $d = ""): string => (string) (getenv($k) ?: $d);
        $form = http_build_query([
            "install" => 2, "db_type" => "mysqli",
            "hostname" => $e("MANTIS_DB_HOST", "db"), "database_name" => $e("MANTIS_DB_NAME", "bugtracker"),
            "db_username" => $e("MANTIS_DB_USER", "mantis"), "db_password" => $e("MANTIS_DB_PASSWORD"),
            "admin_username" => $e("MANTIS_DB_USER", "mantis"), "admin_password" => $e("MANTIS_DB_PASSWORD"),
            "db_exists" => 1, "timezone" => $e("TZ", "UTC"), "path" => $e("MANTIS_PATH"),
        ]);
        $out = file_get_contents("http://127.0.0.1:8099/admin/install.php", false, stream_context_create(["http" => [
            "method" => "POST", "header" => "Content-Type: application/x-www-form-urlencoded", "content" => $form, "timeout" => 600]]));
        file_put_contents("/tmp/install.html", (string) $out);
    '
    kill "$srv" 2>/dev/null || true
    wait "$srv" 2>/dev/null || true
    if [ ! -f config/config_inc.php ]; then
        echo "!!! the installer did not write config/config_inc.php" >&2
        sed -e 's/<[^>]*>//g' /tmp/install.html | grep -iE 'BAD|error|fail' | head -20 >&2
        exit 1
    fi
    # Settings from the environment on top of what the installer wrote.
    cat >> config/config_inc.php <<'PHP'

# --- added by the ePHPm recipe ---------------------------------------------
# Attachments on disk, in their own volume.
$g_file_upload_method = DISK;
$g_absolute_path_default_upload_folder = '/var/lib/mantisbt/attachments/';
# admin/ stays in the image for `php admin/upgrade_unattended.php`, but is
# refused over HTTP by ePHPm's blocked_paths, so the "delete admin/" warning
# is turned off.
$g_admin_checks = OFF;
if( getenv( 'MANTIS_WEBMASTER_EMAIL' ) ) { $g_webmaster_email = getenv( 'MANTIS_WEBMASTER_EMAIL' ); }
if( getenv( 'MANTIS_FROM_EMAIL' ) ) { $g_from_email = getenv( 'MANTIS_FROM_EMAIL' ); }
if( getenv( 'MANTIS_SMTP_HOST' ) ) { $g_phpMailer_method = PHPMAILER_METHOD_SMTP; $g_smtp_host = getenv( 'MANTIS_SMTP_HOST' ); }
PHP
    echo "==> MantisBT installed"
else
    php admin/upgrade_unattended.php || echo "!!! admin/upgrade_unattended.php failed" >&2
fi

# The installer creates `administrator` / `root`: set the configured
# credentials (retried on every start until it has succeeded once).
if [ ! -f config/.ephpm-admin-set ] && [ -n "${MANTIS_ADMIN_PASSWORD:-}" ]; then
    php /usr/local/share/mantisbt/setup.php && touch config/.ephpm-admin-set
fi

case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
