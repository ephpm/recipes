#!/usr/bin/env bash
# Smoke test: Typecho's CLI installer ran on the first start, the blog home
# page renders, the admin logs in through the login form, publishes a post
# through the write-post form, and the post shows on the home page and at
# its own URL. Runs the MariaDB stack, then the SQLite single container.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28409
recipe_init typecho
# Links, redirects and the login cookie are built from the site URL.
export TYPECHO_SITE_URL="$BASE"
export TYPECHO_USER_PASSWORD="Recipe-Typecho-9731"

# form_action PAGE-URL — print the action URL (with its `_` token) of the
# first <form> on the page; Typecho's token is tied to the page's URL, which
# must then be sent as the Referer.
form_action() {
    curl -s --max-time 60 -b "$jar" -c "$jar" "$1" \
        | grep -oE '<form[^>]*action="[^"]*"' | sed -nE 's/.*action="([^"]*)".*/\1/p' | head -1 | sed 's/&amp;/\&/g'
}

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 240
    expect_body "$BASE/" 'Typecho'

    # 1. log in through the login form
    jar="$(cookie_jar)"
    local action loc
    action="$(form_action "$BASE/admin/login.php")"
    [ -n "$action" ] || { echo "!!! no login form" >&2; return 1; }
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' -b "$jar" -c "$jar" -e "$BASE/admin/login.php" \
        --data-urlencode "name=admin" --data-urlencode "password=$TYPECHO_USER_PASSWORD" \
        --data-urlencode "referer=$BASE/admin/" "$action")"
    case "$loc" in
        */admin/*) echo "==> logged in, redirected to $loc" ;;
        *) echo "!!! login redirected to '$loc'" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac
    # the first login lands on admin/welcome.php (which sets a first-run cookie)
    expect_body "$BASE/admin/" 'write-post\.php' -L -b "$jar" -c "$jar"
    expect_body "$BASE/admin/write-post.php" 'name="title"' -b "$jar" -c "$jar"

    # 2. publish a post through the editor form
    action="$(form_action "$BASE/admin/write-post.php")"
    [ -n "$action" ] || { echo "!!! no write-post form" >&2; return 1; }
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' -b "$jar" -c "$jar" -e "$BASE/admin/write-post.php" \
        --data-urlencode "title=Hello from ePHPm" --data-urlencode "text=Published by the recipe smoke test." \
        --data-urlencode "do=publish" --data-urlencode "visibility=publish" --data-urlencode "markdown=1" \
        --data-urlencode "allowComment=1" --data-urlencode "allowPing=1" --data-urlencode "allowFeed=1" \
        --data-urlencode "slug=hello-ephpm" "$action")"
    case "$loc" in
        *manage-posts*) echo "==> post published, redirected to $loc" ;;
        *) echo "!!! publishing redirected to '$loc'" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac

    # 3. read it back from the public site (Typecho lists posts created
    #    before the current second, so give it a moment)
    sleep 2
    expect_body "$BASE/" 'Hello from ePHPm'
    local url
    url="$(curl -s "$BASE/" | tr '\n' ' ' | grep -oE 'href="[^"]*"> *Hello from ePHPm' | head -1 | sed -E 's/href="([^"]*)".*/\1/')"
    [ -n "$url" ] || { echo "!!! no link to the post on the home page" >&2; return 1; }
    echo "==> post URL: $url (the default /index.php/archives/<id>/ permalinks, no PATH_INFO needed)"
    expect_body "$url" 'Published by the recipe smoke test'

    # 4. private paths
    expect_status "$BASE/config.inc.php" 403
    expect_status "$BASE/var/Typecho/Common.php" 403

    rm -f "$jar"
    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.sqlite.yml
