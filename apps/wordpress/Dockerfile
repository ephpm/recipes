# WordPress on ePHPm.
#
# One container replaces nginx/apache + php-fpm + Redis: ePHPm serves the
# files, runs PHP, and provides the persistent object cache in-process
# (the ephpm/cache-wordpress drop-in talks to the embedded KV store).
#
# Build args:
#   EPHPM_TAG   ephpm/ephpm image tag (default v0.11.3-php8.5)
#   WP_VERSION  WordPress release to bake in (default 7.1.3)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG WP_VERSION=7.1.3

# ── Stage 1: fetch WordPress, WP-CLI and the object-cache drop-in ────────────
FROM docker.io/library/alpine:3.20 AS src
ARG WP_VERSION
RUN apk add --no-cache curl git tar
RUN mkdir -p /src \
    && curl -fsSL "https://wordpress.org/wordpress-${WP_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src
# Persistent object cache over ePHPm's in-process KV (replaces Redis + the
# Redis Object Cache plugin). Pinned to a tag of github.com/ephpm/cache-wordpress.
RUN git clone --depth 1 --branch v0.1.2 https://github.com/ephpm/cache-wordpress \
       /src/wp-content/cache-wordpress \
    && rm -rf /src/wp-content/cache-wordpress/.git \
    && printf '<?php\nrequire __DIR__ . "/cache-wordpress/dropin/object-cache.php";\n' \
       > /src/wp-content/object-cache.php
RUN curl -fsSL -o /wp-cli.phar \
       https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/html
COPY --from=src /wp-cli.phar /usr/local/lib/wp-cli.phar
COPY wp /usr/local/bin/wp
COPY wp-config.php /var/www/html/wp-config.php
COPY ephpm.toml ephpm.embedded.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/wp /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/www/html/wp-content/uploads /var/lib/ephpm \
    # pristine copy, used by entrypoint.sh to seed an empty wp-content volume
    && mkdir -p /usr/local/share/wordpress \
    && cp -a /var/www/html/wp-content /usr/local/share/wordpress/wp-content

VOLUME ["/var/www/html/wp-content"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
