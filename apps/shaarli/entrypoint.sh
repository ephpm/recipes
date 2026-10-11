#!/bin/sh
# Container entrypoint: make sure Shaarli's writable directories exist (the
# data/ and cache/ volumes may be mounted empty), then ePHPm in the foreground.
set -eu

cd /var/www/shaarli
mkdir -p data cache pagecache tmp

exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@"
