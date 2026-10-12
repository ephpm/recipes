#!/usr/bin/env bash
# Smoke test: wait for migrate + aimeos:setup (demo catalogue) + the admin
# account, browse the shop, put a product in the basket and read the basket
# back, log in to the admin through the Breeze login form, create a product
# through the admin GraphQL API and read it back in the JQAdm product list,
# and check that the `jobs` sidecar ran the Aimeos cron jobs (the demo
# orders' confirmation e-mails, written to the log mailer).
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28520
recipe_init aimeos
export APP_URL="$BASE"
export AIMEOS_ADMIN_PASSWORD="Recipe-Pass-4417"

compose_up
# the login page answers once the entrypoint is done (setup runs before `ephpm serve`)
wait_http "$BASE/login" 200 600
# the base image's E2E fixtures (issues/joomla.md) must not be served
fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
expect_body "$BASE/" 'href="/shop/red-t-shirt"'          # the demo catalogue on the home page

# 1. shop workflow: product page -> add to basket -> basket shows it
jar="$(cookie_jar)"
token="$(form_value "$BASE/shop/red-t-shirt" _token -c "$jar" -b "$jar")"
[ -n "$token" ] || { echo "!!! no _token on the product page" >&2; exit 1; }
expect_body "$BASE/shop/basket" 'Red T-Shirt' -c "$jar" -b "$jar" \
    --data-urlencode "_token=$token" --data "b_action=add&b_prod[0][prodid]=2&b_prod[0][quantity]=2&b_prod[0][stocktype]=default"
expect_body "$BASE/shop/basket" 'Red T-Shirt' -c "$jar" -b "$jar"
rm -f "$jar"

# 2. admin: log in through the login form ...
jar="$(cookie_jar)"
token="$(form_value "$BASE/login" _token -c "$jar" -b "$jar")"
expect_status "$BASE/login" 302 -c "$jar" -b "$jar" --data-urlencode "_token=$token" \
    --data-urlencode "email=admin@example.com" --data-urlencode "password=$AIMEOS_ADMIN_PASSWORD"
expect_body "$BASE/admin/default/jqadm/search/product" 'Aimeos administration interface' -c "$jar" -b "$jar"

# ... create a product through the admin's GraphQL API (what the back-end's
# Vue components call) and read it back, through GraphQL and the JQAdm list
csrf="$(curl -s -c "$jar" -b "$jar" "$BASE/admin/default/jqadm/search/product" \
    | sed -nE 's/.*name="csrf-token" content="([^"]+)".*/\1/p' | head -1)"
[ -n "$csrf" ] || { echo "!!! no csrf-token meta on the admin page" >&2; exit 1; }
expect_body "$BASE/admin/default/graphql" '"code":"ephpm-recipe"' -c "$jar" -b "$jar" \
    -H "X-CSRF-TOKEN: $csrf" -H 'Content-Type: application/json' \
    --data '{"query":"mutation { saveProduct(input: {code: \"ephpm-recipe\", label: \"Made by the ePHPm recipe\", type: \"default\", status: 1}) { id code } }"}'
expect_body "$BASE/admin/default/graphql" 'Made by the ePHPm recipe' -c "$jar" -b "$jar" \
    -H "X-CSRF-TOKEN: $csrf" -H 'Content-Type: application/json' \
    --data '{"query":"query { searchProducts(filter: \"{\\\"==\\\":{\\\"product.code\\\":\\\"ephpm-recipe\\\"}}\") { items { id label } } }"}'
expect_body "$BASE/admin/default/jqadm/search/product?filter%5Bkey%5D%5B0%5D=product.code&filter%5Bop%5D%5B0%5D=%3D%3D&filter%5Bval%5D%5B0%5D=ephpm-recipe" \
    'Made by the ePHPm recipe' -c "$jar" -b "$jar"
rm -f "$jar"

# 3. the jobs sidecar ran `aimeos:jobs` (order e-mails for the demo orders)
i=0
until compose logs jobs 2>/dev/null | grep -a 'Subject: Your order' >/dev/null; do
    i=$((i + 1)); [ "$i" -ge 120 ] && { echo "!!! the jobs service sent no order e-mail" >&2; compose logs --tail=40 jobs >&2; exit 1; }
    sleep 1
done
echo "==> jobs service ran aimeos:jobs (order confirmation e-mail in the log mailer)"

# 4. artisan on the embedded PHP; re-spawned PHP is the `php` shim, not `ephpm`
run_in ephpm sh -c 'b="$(ephpm php -r "require \"vendor/autoload.php\"; echo Illuminate\Console\Application::phpBinary();" 2>/dev/null)"; echo "phpBinary: $b"; eval "$b artisan --version"' \
    || { echo "!!! <phpBinary> artisan does not run" >&2; exit 1; }
