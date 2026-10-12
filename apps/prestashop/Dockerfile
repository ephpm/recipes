# PrestaShop on ePHPm.
#
# One container replaces the official prestashop/prestashop image
# (php-apache with mod_rewrite): ePHPm serves the shop and runs PHP.
#
# Build args:
#   EPHPM_TAG           ephpm/ephpm image tag (default v0.11.3-php8.5)
#   PRESTASHOP_ZIP      release archive (default: PrestaShop 9.2.0 from the
#                       same distribution API the official image builds from)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG PRESTASHOP_ZIP=https://api.prestashop-project.org/assets/prestashop-classic/9.2.0-6.0/prestashop.zip

# ── Stage 1: fetch and unpack the release (a zip holding prestashop.zip) ─────
FROM docker.io/library/alpine:3.20 AS src
ARG PRESTASHOP_ZIP
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /ps.zip "${PRESTASHOP_ZIP}" \
    && mkdir /x /src && unzip -q /ps.zip -d /x && unzip -q /x/prestashop.zip -d /src \
    && rm -rf /ps.zip /x

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# Pristine copy; entrypoint.sh copies it into the /var/www/prestashop volume on the
# first start, like the official image (PrestaShop writes into its own tree:
# config, modules, themes, images).
COPY --from=src /src /usr/src/prestashop
COPY front.php /usr/src/prestashop/ephpm-front.php
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && mkdir -p /var/lib/ephpm /var/www/prestashop

# (not /var/www/html: the ephpm/ephpm base image ships demo files there,
# which would be copied into a fresh named volume)
WORKDIR /var/www/prestashop
VOLUME ["/var/www/prestashop"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
