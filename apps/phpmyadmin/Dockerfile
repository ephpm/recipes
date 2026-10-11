# phpMyAdmin on ePHPm.
#
# One container replaces Apache + mod_php (the phpmyadmin:apache image):
# ePHPm serves the files and runs PHP, with sessions in its in-process KV
# store. phpMyAdmin manages the compose stack's `db` service.
#
# Build args:
#   EPHPM_TAG    ephpm/ephpm image tag (default v0.11.3-php8.5)
#   PMA_VERSION  phpMyAdmin release to bake in (default 5.2.3)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG PMA_VERSION=5.2.3

# ── Stage 1: the release tarball (vendor/ included) ─────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG PMA_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && cd /src \
    # same trims as the official image: the web setup wizard, examples, JS sources
    && rm -rf setup examples js/src babel.config.json doc/html/_sources "RELEASE-DATE-${PMA_VERSION}" \
       CONTRIBUTING.md composer.json composer.lock package.json yarn.lock \
    # read the config from /etc/phpmyadmin, as the official image does
    && grep -q -F "'configFile' => ROOT_PATH . 'config.inc.php'," libraries/vendor_config.php \
    && sed -i "s@'configFile' => .*@'configFile' => '/etc/phpmyadmin/config.inc.php',@" libraries/vendor_config.php \
    && grep -q -F "'configFile' => '/etc/phpmyadmin/config.inc.php'," libraries/vendor_config.php \
    # WORKAROUND for ePHPm v0.11.3 (see ../../issues/phpmyadmin.md): phpMyAdmin
    # renders every page from a shutdown function (ResponseRenderer::response)
    # that ends in `exit;`, and ePHPm reports an exit() inside a shutdown
    # function as a Zend bailout — 500, response discarded. Returning from the
    # shutdown function instead is equivalent there. Remove once ePHPm is fixed.
    && grep -q -F '        $buffer->flush();' libraries/classes/ResponseRenderer.php \
    && awk 'prev ~ /^        \$buffer->flush\(\);$/ && $0 == "        exit;" { print "        return; // ePHPm recipe: was `exit;` — see issues/phpmyadmin.md"; prev = $0; next } { print; prev = $0 }' \
         libraries/classes/ResponseRenderer.php > /tmp/rr.php && mv /tmp/rr.php libraries/classes/ResponseRenderer.php \
    && grep -q -F 'return; // ePHPm recipe' libraries/classes/ResponseRenderer.php

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/html
COPY config.inc.php /etc/phpmyadmin/config.inc.php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /etc/phpmyadmin/conf.d /var/www/html/tmp \
    && chmod 1777 /var/www/html/tmp

WORKDIR /var/www/html
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
