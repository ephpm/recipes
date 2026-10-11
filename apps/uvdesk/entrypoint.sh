#!/bin/sh
# Container entrypoint: what UVdesk's web setup wizard does, unattended —
# schema + fixtures (`uvdesk_wizard:database:migrate`) and the first super
# admin (`uvdesk_wizard:defaults:create-user`) — on the first start, then
# ePHPm in the foreground.
set -eu

cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# public/assets (attachments, avatars) is a volume; seed it when empty.
[ -n "$(ls -A public/assets 2>/dev/null)" ] || cp -a /usr/local/share/uvdesk/assets/. public/assets/ 2>/dev/null || true

: "${DATABASE_URL:?DATABASE_URL must be set (mysql://user:pass@host:3306/db?serverVersion=...)}"
: "${APP_SECRET:?APP_SECRET must be set}"

# The wizard writes the site URL into config/packages/uvdesk.yaml (links in
# e-mails are built from it); do the same from UVDESK_SITE_URL.
if [ -n "${UVDESK_SITE_URL:-}" ]; then
    sed -i "s|^    site_url: .*|    site_url: '${UVDESK_SITE_URL#*://}'|" config/packages/uvdesk.yaml
fi

db_host="$(ephpm php -r '$u = parse_url(getenv("DATABASE_URL")); echo $u["host"] ?? "db";')"
db_port="$(ephpm php -r '$u = parse_url(getenv("DATABASE_URL")); echo $u["port"] ?? 3306;')"
echo "==> waiting for database at $db_host:$db_port"
i=0
until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$db_host" "$db_port" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 90 ] && { echo "!!! database at $db_host not reachable after 90 tries" >&2; exit 1; }
    sleep 2
done

rm -rf var/cache/*
installed() {
    ephpm php -r '
        $u = parse_url(getenv("DATABASE_URL"));
        mysqli_report(MYSQLI_REPORT_OFF);
        $c = @mysqli_connect($u["host"], urldecode($u["user"] ?? ""), urldecode($u["pass"] ?? ""), ltrim($u["path"] ?? "", "/"), (int) ($u["port"] ?? 3306));
        $r = $c ? mysqli_query($c, "SHOW TABLES LIKE \x27uv_user\x27") : false;
        exit($r && mysqli_num_rows($r) > 0 ? 0 : 1);
    '
}

if ! installed; then
    echo "==> creating the schema and loading the default data"
    # --env=dev: the wizard command loads its default data with
    # doctrine:fixtures:load, and the skeleton enables DoctrineFixturesBundle
    # only in the dev/test environments (the web wizard runs in the
    # skeleton's default APP_ENV=dev). The server itself runs in prod.
    uvdesk uvdesk_wizard:database:migrate --no-interaction --env=dev
    if [ -n "${UVDESK_ADMIN_EMAIL:-}" ] && [ -n "${UVDESK_ADMIN_PASSWORD:-}" ]; then
        echo "==> creating the super admin $UVDESK_ADMIN_EMAIL"
        uvdesk uvdesk_wizard:defaults:create-user ROLE_SUPER_ADMIN \
            "${UVDESK_ADMIN_NAME:-Admin}" "$UVDESK_ADMIN_EMAIL" "$UVDESK_ADMIN_PASSWORD" --no-interaction
    else
        echo "==> UVDESK_ADMIN_EMAIL/UVDESK_ADMIN_PASSWORD unset: create the admin with"
        echo "    docker compose exec ephpm uvdesk uvdesk_wizard:defaults:create-user ROLE_SUPER_ADMIN"
    fi
fi
uvdesk cache:warmup --no-interaction >/dev/null
echo "==> UVdesk is ready"

exec ephpm serve --config "$CONFIG"
