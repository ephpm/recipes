#!/bin/sh
# Container entrypoint: make sure the data directory exists (the volume may be
# mounted empty), then ePHPm in the foreground.
set -eu

mkdir -p /srv/data

exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@"
