#!/usr/bin/env bash
# Smoke test: the entrypoint runs OpenCart's CLI installer (schema, demo
# catalogue, admin); the storefront home page must render, and the admin
# login page must answer.
#
# BLOCKED on ePHPm v0.11.3: the home page's "Featured" module resizes the
# demo catalogue's JPEG product images with GD, and the SDK's GD has no
# JPEG support, so the storefront renders "Call to undefined function
# imagecreatefromjpeg()" instead of the shop (see the README). This test
# fails on that check today; it is kept so the recipe can be re-checked once
# the SDK's GD gains JPEG support.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28509
recipe_init opencart
export OPENCART_URL="$BASE"
export OPENCART_ADMIN_EMAIL="admin@example.com"
export OPENCART_ADMIN_PASSWORD="Recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 600
    expect_status "$BASE/admin/" 200
    # the storefront itself (OpenCart prints PHP errors with status 200)
    local body
    body="$(curl -s --max-time 60 "$BASE/")"
    case "$body" in
        *"Call to undefined function"*|*"Backtrace:"*)
            echo "!!! the storefront home page renders a PHP error:" >&2
            printf '%s\n' "$body" | head -n 4 >&2
            return 1 ;;
    esac
    expect_body "$BASE/" "Your Store|OpenCart"
    compose down -v --remove-orphans
}

run_variant compose.yml
