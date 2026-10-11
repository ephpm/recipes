# Yii 2 on ePHPm — the official `yiisoft/yii2-app-basic` template.
#
# For your own application replace the `create-project` line with
# `COPY . /app` + `composer install` and keep config/db.php env-driven.
#
# Build args:
#   EPHPM_TAG    ephpm/ephpm image tag (default v0.11.3-php8.5)
#   YII_VERSION  yiisoft/yii2-app-basic version (default 2.0.54 — the 2.0.55
#                release ships a models/LoginForm.php with an unterminated
#                docblock, a ParseError on every login; fixed on master)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG YII_VERSION=2.0.54

FROM docker.io/library/composer:2 AS vendor
ARG YII_VERSION
# --no-scripts: post-create-project-cmd only sets cookieValidationKey and
# directory permissions; both are handled below / in entrypoint.sh.
RUN composer create-project --no-interaction --prefer-dist --no-dev --no-scripts \
        --ignore-platform-reqs yiisoft/yii2-app-basic /app "${YII_VERSION}"
WORKDIR /app
COPY demo/db.php config/db.php
# cookieValidationKey from the environment (generated once by entrypoint.sh
# when not provided).
RUN sed -i "s/'cookieValidationKey' => ''/'cookieValidationKey' => getenv('COOKIE_VALIDATION_KEY') ?: ''/" config/web.php \
    && grep -q "COOKIE_VALIDATION_KEY" config/web.php
# Pretty URLs (/site/login instead of /index.php?r=site%2Flogin) — the
# template ships this block commented out; ePHPm's fallback rule routes
# every path to index.php like web/.htaccess would.
RUN sed -i "s/^return \$config;/\$config['components']['urlManager'] = ['enablePrettyUrl' => true, 'showScriptName' => false, 'rules' => []];\nreturn \$config;/" config/web.php \
    && grep -q "enablePrettyUrl" config/web.php
# Yii's ErrorHandler ends every uncaught exception (404s included) with
# exit(1) inside the PHP exception handler; ePHPm v0.11.3 reports an exit()
# there as a bailout and replaces the rendered error page with a bare 500
# (issues/yii2.md). silentExitOnException skips that exit — the error page
# and its status code (404, 400, …) are sent as normal.
RUN sed -i "s/^return \$config;/\$config['components']['errorHandler']['silentExitOnException'] = true;\nreturn \$config;/" config/web.php \
    && grep -q "silentExitOnException" config/web.php
# The template hard-codes YII_DEBUG=true / YII_ENV=dev in web/index.php and
# the `yii` console script (which then bootstraps the dev-only gii/debug
# modules). Read them from the environment instead, defaulting to prod.
RUN for f in web/index.php yii; do \
        sed -i "s/define('YII_DEBUG', true)/define('YII_DEBUG', getenv('YII_DEBUG') === '1')/; s/define('YII_ENV', 'dev')/define('YII_ENV', getenv('YII_ENV') ?: 'prod')/" "$f" \
        && grep -q "getenv('YII_ENV')" "$f"; \
    done

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
COPY --from=vendor /app /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /app
ENV YII_ENV=prod \
    YII_DEBUG=0 \
    DB_DSN="mysql:host=127.0.0.1;port=3306;dbname=yii2basic" \
    DB_USER=root \
    DB_PASSWORD=
RUN chmod +x /usr/local/bin/entrypoint.sh && mkdir -p /var/lib/ephpm runtime web/assets

VOLUME ["/app/runtime", "/app/web/assets"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
