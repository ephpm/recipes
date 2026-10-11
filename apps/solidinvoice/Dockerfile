# SolidInvoice on ePHPm.
#
# One container replaces the official solidinvoice/solidinvoice image (a
# single static FrankenPHP binary with Caddy): ePHPm serves public/ and runs
# PHP in per-request mode; the Symfony front-controller rewrite comes from
# ephpm.toml.
#
# Build args:
#   EPHPM_TAG             ephpm/ephpm image tag (default v0.11.3-php8.4 — SolidInvoice 3 targets PHP 8.4)
#   SOLIDINVOICE_VERSION  SolidInvoice release to bake in (default 3.0.1)

ARG EPHPM_TAG=v0.11.3-php8.4
ARG SOLIDINVOICE_VERSION=3.0.1

# ── Stage 1: fetch the release tarball (vendor/ and built assets included) ───
FROM docker.io/library/alpine:3.20 AS src
ARG SOLIDINVOICE_VERSION
RUN apk add --no-cache curl tar
RUN curl -fsSL -o /si.tar.gz \
        "https://github.com/SolidInvoice/SolidInvoice/releases/download/${SOLIDINVOICE_VERSION}/SolidInvoice-${SOLIDINVOICE_VERSION}.tar.gz" \
    && mkdir /src && tar xzf /si.tar.gz -C /src && rm /si.tar.gz \
    # build tooling and packaging material that is not needed to run the app
    && rm -rf /src/frankenphp /src/docker /src/packaging /src/helm /src/tests \
              /src/.github /src/docker-bake.hcl /src/var/cache/* /src/var/log/* \
    && mkdir -p /src/var/cache /src/var/log

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
COPY ephpm.toml /etc/ephpm/
COPY solidinvoice /usr/local/bin/solidinvoice
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /app
RUN chmod +x /usr/local/bin/solidinvoice /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm /etc/solidinvoice

# Same config/secrets directory as the official image (a volume).
ENV SOLIDINVOICE_ENV=prod \
    SOLIDINVOICE_DEBUG=0 \
    SOLIDINVOICE_CONFIG_DIR=/etc/solidinvoice
VOLUME ["/etc/solidinvoice"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
