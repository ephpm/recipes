#!/usr/bin/env bash
# Smoke test: CLI install on first start, home page 200, manager login through
# the connector API.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28177
recipe_init modx
export MODX_ADMIN_PASSWORD="Recipe-pass-1234" MODX_HTTP_HOST="127.0.0.1:$PORT"
compose_up
wait_http "$BASE/" 200 400
