# LimeSurvey on ePHPm.
#
# One container replaces Apache + mod_php (the widely used
# martialblog/limesurvey image): ePHPm serves the tree and routes every
# non-file URL to index.php; the console (install, updatedb) runs on the
# embedded PHP.
#
# Build args:
#   EPHPM_TAG            ephpm/ephpm image tag (default v0.11.3-php8.5)
#   LIMESURVEY_VERSION   LimeSurvey release tag (default 7.5.0+261001)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG LIMESURVEY_VERSION=7.5.0+261001

# ── Stage 1: the release tag (vendor/ and built assets are committed) ────────
FROM docker.io/library/alpine:3.20 AS src
ARG LIMESURVEY_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/LimeSurvey/LimeSurvey/archive/refs/tags/$(echo "${LIMESURVEY_VERSION}" | sed 's/+/%2B/').tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/docs /src/editor/src /src/editor/__mocks__ /src/editor/scripts

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# the base image's E2E fixtures (issues/joomla.md) must not be served next to the app
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY config.php /var/www/html/application/config/config.php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH (and PHP_BINARY for Symfony/Yii helpers that re-invoke PHP,
# see issues/pterodactyl.md): the embedded CLI.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php \
    && chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/limesurvey /var/lib/ephpm \
    # security.php (the encryption keys LimeSurvey generates on first use)
    # must survive container re-creation: keep it in the /var/limesurvey volume
    && ln -sfn /var/limesurvey/security.php /var/www/html/application/config/security.php \
    # pristine upload/ to seed its volume
    && cp -a /var/www/html/upload /usr/local/share/limesurvey-upload
ENV PHP_BINARY=/usr/local/bin/php

WORKDIR /var/www/html
VOLUME ["/var/www/html/upload", "/var/limesurvey"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
