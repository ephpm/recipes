#!/usr/bin/env bash
# Smoke test: the demo blog renders from the database, the admin logs in
# through the CSRF-protected login form, and a new post is created from the
# admin form and appears on the public blog. Runs the MariaDB stack and the
# app-native SQLite single-container stack.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28012
recipe_init symfony

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/en/blog/" 200 240
    # fixtures loaded (the embedded variant loads them in the background)
    local i=0
    until curl -s "$BASE/en/blog/" | grep -E 'class="post"|<article' >/dev/null; do
        i=$((i + 1)); [ "$i" -ge 90 ] && { echo "!!! no posts rendered"; compose logs --tail=60 ephpm; return 1; }
        sleep 2
    done
    echo "==> blog posts rendered from the database"

    local jar tok; jar="$(cookie_jar)"
    tok="$(form_value "$BASE/en/login" "_csrf_token" -c "$jar" -b "$jar")"
    [ -n "$tok" ] || { echo "!!! no CSRF token on the login form"; return 1; }
    # Symfony's stateless CSRF needs a same-origin Origin/Referer when the
    # JS double-submit cookie is absent (curl is a browser without JS).
    expect_status "$BASE/en/login" 302 -c "$jar" -b "$jar" -H "Origin: $BASE" -e "$BASE/en/login" \
        --data-urlencode "_username=jane_admin" --data-urlencode "_password=kitten" --data-urlencode "_csrf_token=$tok"
    expect_body "$BASE/en/admin/post/" "Jane Doe|Logout|logout" -b "$jar"
    echo "==> logged in as jane_admin"

    # Create a post through the admin form.
    tok="$(form_value "$BASE/en/admin/post/new" "post\[_token\]" -c "$jar" -b "$jar")"
    [ -n "$tok" ] || { echo "!!! no CSRF token on the new-post form"; return 1; }
    expect_status "$BASE/en/admin/post/new" 303 -c "$jar" -b "$jar" -H "Origin: $BASE" -e "$BASE/en/admin/post/new" \
        --data-urlencode "post[title]=Hello from ePHPm" \
        --data-urlencode "post[summary]=Created by the recipe smoke test." \
        --data-urlencode "post[content]=This post was created through the admin form on ePHPm." \
        --data-urlencode "post[publishedAt]=$(date -u +'%Y-%m-%d %H:%M')" \
        --data-urlencode "post[tags]=ephpm" \
        --data-urlencode "post[_token]=$tok"
    expect_body "$BASE/en/admin/post/" "Hello from ePHPm" -b "$jar"      # admin list
    expect_body "$BASE/en/blog/search?q=ePHPm" "Hello from ePHPm"       # public search
    rm -f "$jar"

    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.sqlite.yml
