#!/usr/bin/env bash
# Smoke test: the entrypoint runs PrestaShop's CLI installer; the shop's home
# page answers and the back-office login page is served through the
# per-prefix front controller.
#
# BLOCKED on ePHPm v0.11.3: the installer's theme step calls
# imagecreatefromjpeg(), which the SDK's GD build does not have (see the
# README), so this test fails at the install today. It is kept so the recipe
# can be re-checked as soon as the SDK's GD gains JPEG support.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28508
recipe_init prestashop
export PS_DOMAIN="127.0.0.1:${PORT}"
export PS_FOLDER_ADMIN="admin-shop"
export ADMIN_MAIL="admin@example.com"
export ADMIN_PASSWD="Recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    for _ in $(seq 1 300); do
        compose logs ephpm 2>/dev/null | grep -E "PrestaShop is ready|!!!" >/dev/null && break
        sleep 2
    done
    if compose logs ephpm 2>/dev/null | grep "!!!" >/dev/null; then
        echo "!!! installation failed" >&2
        compose logs --tail=40 ephpm >&2
        return 1
    fi
    wait_http "$BASE/" 200 120
    expect_body "$BASE/" "PrestaShop|prestashop"
    expect_status "$BASE/$PS_FOLDER_ADMIN/index.php?controller=AdminLogin" 200
    compose down -v --remove-orphans
}

run_variant compose.yml
