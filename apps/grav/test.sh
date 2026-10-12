#!/usr/bin/env bash
# Smoke test: the home page renders, the admin account the entrypoint
# created with Grav's CLI (`bin/plugin login new-user`) logs in through the
# API plugin (the admin2 panel's own login call), a page created through the
# API is served at its route, the admin panel loads, and private paths are
# refused.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28405
recipe_init grav
export GRAV_ADMIN_USER=admin
export GRAV_ADMIN_PASSWORD="Recipe-Grav-9731"

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 180
    # the base image's E2E fixtures (issues/joomla.md) must not be served
    fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
    expect_body "$BASE/" "Grav"
    expect_body "$BASE/typography" "Typography"          # a page route through the fallback
    expect_status "$BASE/admin" 200                      # the admin2 panel

    # 1. log in: exchange the admin's credentials for an API token
    local resp token
    resp="$(curl -s --max-time 60 -H 'Content-Type: application/json' \
        --data "{\"username\":\"$GRAV_ADMIN_USER\",\"password\":\"$GRAV_ADMIN_PASSWORD\"}" "$BASE/api/v1/auth/token")"
    token="$(printf '%s' "$resp" | sed -nE 's/.*"access_token":"([^"]+)".*/\1/p')"
    [ -n "$token" ] || { echo "!!! login failed: $(printf '%s' "$resp" | head -c 600)" >&2; compose logs --tail=60 ephpm >&2; return 1; }
    echo "==> logged in through /api/v1/auth/token"

    # 2. create a page and read it back, through the API and the site itself
    resp="$(curl -s --max-time 60 -H "X-API-Token: $token" -H 'Content-Type: application/json' \
        --data '{"route":"/hello-ephpm","title":"Hello from ePHPm","content":"Created by the **recipe smoke test**."}' \
        "$BASE/api/v1/pages")"
    case "$resp" in
        *'hello-ephpm'*) echo "==> page created through the API" ;;
        *) echo "!!! creating a page failed: $(printf '%s' "$resp" | head -c 600)" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac
    expect_body "$BASE/api/v1/pages/hello-ephpm" '"title":"Hello from ePHPm"' -H "X-API-Token: $token"
    expect_body "$BASE/hello-ephpm" '<strong>recipe smoke test</strong>'

    # 3. private paths are refused (accounts hold password hashes)
    expect_status "$BASE/user/accounts/admin.yaml" 403
    expect_status "$BASE/user/config/system.yaml" 403
    expect_status "$BASE/user/pages/01.home/default.md" 403
    expect_status "$BASE/cache/" 403

    # 4. Grav's CLI on the embedded PHP
    local out
    out="$(run_in ephpm ephpm php bin/grav clearcache)"
    case "$out" in
        *"Cleared:"*) echo "==> bin/grav clearcache ran" ;;
        *) echo "!!! bin/grav clearcache: $out" >&2; return 1 ;;
    esac

    compose down -v --remove-orphans
}

run_variant compose.yml
