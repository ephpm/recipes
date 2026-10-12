# FileGator on ePHPm.
#
# One container replaces the official image's Apache + mod_php: ePHPm serves
# dist/ (the single front controller and the built Vue frontend) and runs
# PHP. The release build from filegator/static (vendor/ and the compiled
# frontend included) is used as is: no Composer or Node stage.
#
# Build args:
#   EPHPM_TAG          ephpm/ephpm image tag (default v0.11.3-php8.5)
#   FILEGATOR_VERSION  FileGator release (default 7.16.5)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG FILEGATOR_VERSION=7.16.5

# ── Stage 1: the release build ──────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG FILEGATOR_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /fg.zip "https://raw.githubusercontent.com/filegator/static/master/builds/filegator_v${FILEGATOR_VERSION}.zip" \
    && unzip -q /fg.zip -d / \
    && grep -q "APP_VERSION', '${FILEGATOR_VERSION}'" /filegator/dist/index.php \
    && cd /filegator \
    # the development entry point and the repo's own build files
    && rm -rf index.php configuration.php Dockerfile* docker-compose*.yml package*.json \
              BACKERS.md CODE_OF_CONDUCT.md CONTRIBUTING.md SECURITY.md

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /filegator /var/www/filegator
COPY configuration.php /var/www/filegator/configuration.php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    # pristine copy, used by entrypoint.sh to seed an empty private volume
    && cp -a /var/www/filegator/private /usr/local/share/filegator-private

WORKDIR /var/www/filegator
VOLUME ["/var/www/filegator/repository", "/var/www/filegator/private"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
