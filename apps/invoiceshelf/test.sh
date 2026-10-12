#!/usr/bin/env bash
# Smoke test: InvoiceShelf migrates, seeds and finishes its installation
# wizard unattended on the first start; the app answers; the admin logs in
# through the API (Sanctum token, the mobile-app login); a customer and an
# invoice (due in the past) are created and read back; the invoice is
# marked sent; and the scheduler's `check:invoices:status` job — run by
# Laravel as a child PHP process — flags it overdue.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28416
recipe_init invoiceshelf
export APP_URL="$BASE"
export SANCTUM_STATEFUL_DOMAINS="127.0.0.1:${PORT}" SESSION_DOMAIN="127.0.0.1"
export INVOICESHELF_ADMIN_PASSWORD="recipe-pass-123"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 300
    expect_body "$BASE/login" 'InvoiceShelf'
    expect_status "$BASE/info.php" 404              # no ePHPm test fixtures (docroot is /app/public)

    local api="$BASE/api/v1" token out id
    local -a json=(-H "Accept: application/json" -H "Content-Type: application/json")

    # 1a. the web UI's login: Sanctum SPA cookies (XSRF cookie echoed as a header)
    local jar xsrf
    jar="$(cookie_jar)"
    curl -s -o /dev/null -c "$jar" -b "$jar" "$BASE/sanctum/csrf-cookie"
    xsrf="$(awk '$6=="XSRF-TOKEN"{print $7}' "$jar" | sed 's/%3D/=/g')"
    expect_status "$BASE/login" 204 -c "$jar" -b "$jar" "${json[@]}" -H "X-XSRF-TOKEN: $xsrf" \
        -H "Referer: $BASE/login" --data "{\"email\":\"admin@example.com\",\"password\":\"$INVOICESHELF_ADMIN_PASSWORD\"}"
    xsrf="$(awk '$6=="XSRF-TOKEN"{print $7}' "$jar" | sed 's/%3D/=/g')"
    expect_body "$api/me" '"role":"super admin"' -b "$jar" -H "Accept: application/json" \
        -H "X-XSRF-TOKEN: $xsrf" -H "Referer: $BASE/admin"
    rm -f "$jar"

    # 1b. log in through the token API (used by the mobile app) for the rest
    out="$(curl -s "${json[@]}" "$api/auth/login" \
        --data "{\"username\":\"admin@example.com\",\"password\":\"$INVOICESHELF_ADMIN_PASSWORD\",\"device_name\":\"recipes\"}")"
    token="$(printf '%s' "$out" | sed -nE 's/.*"token":"([^"]+)".*/\1/p')"
    [ -n "$token" ] || { echo "!!! login: $out" >&2; return 1; }
    json+=(-H "Authorization: Bearer $token")
    expect_body "$api/me" '"email":"admin@example.com"' "${json[@]}"

    # 2. a customer and an invoice for it, read back
    expect_body "$api/customers" '"name":"Hello from ePHPm"' "${json[@]}" \
        --data '{"name":"Hello from ePHPm","email":"hello@example.com","currency_id":1}'
    out="$(curl -s "${json[@]}" "$api/invoices" --data '{"invoice_date":"2026-09-01","due_date":"2026-09-15","customer_id":1,"invoice_number":"INV-000001","discount":0,"discount_val":0,"discount_type":"fixed","sub_total":10000,"total":10000,"tax":0,"template_name":"invoice1","exchange_rate":1,"taxes":[],"items":[{"name":"Recipe smoke test","description":"","quantity":1,"price":10000,"total":10000,"discount":0,"discount_val":0,"discount_type":"fixed","tax":0}]}')"
    id="$(printf '%s' "$out" | sed -nE 's/^\{"data":\{"id":([0-9]+).*/\1/p')"
    [ -n "$id" ] || { echo "!!! invoice not created: $(printf '%s' "$out" | head -c 400)" >&2; return 1; }
    echo "==> invoice $id created"
    expect_body "$api/invoices/$id" '"invoice_number":"INV-000001"' "${json[@]}"
    expect_body "$api/invoices?customer_id=1" '"name":"Recipe smoke test"|"INV-000001"' "${json[@]}"
    expect_body "$api/invoices/$id/status" '"success":true' "${json[@]}" --data '{"status":"SENT"}'

    # 3. the scheduler's job, as Laravel runs it (a child `php artisan …`
    #    found through PHP_BINARY), flags the past-due invoice
    out="$(run_in scheduler php artisan schedule:test --name=check:invoices:status --no-ansi)"
    printf '%s' "$out" | grep -q "'/usr/local/bin/php' 'artisan' check:invoices:status" \
        || { echo "!!! scheduler did not spawn the php shim: $out" >&2; return 1; }
    expect_body "$api/invoices/$id" '"overdue":(1|true)' "${json[@]}"
    echo "==> scheduled job ran (invoice flagged overdue)"

    compose down -v --remove-orphans
}

run_variant compose.yml
