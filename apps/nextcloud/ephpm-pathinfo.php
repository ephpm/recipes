<?php
/**
 * auto_prepend_file for Nextcloud on ePHPm: nginx's fastcgi_split_path_info.
 *
 * Nextcloud addresses its PHP entry points with a trailing path —
 * /remote.php/dav/files/alice/x.txt (WebDAV), /ocs/v2.php/apps/...,
 * /public.php/dav/..., /index.php/apps/files — which nginx splits at the
 * `.php` segment (fastcgi_split_path_info) and Apache at AcceptPathInfo.
 * ePHPm v0.11.3 does neither: such a path is not a file, so `[server]
 * fallback` hands it to /index.php. This file runs first on every request and,
 * when the request path names one of the entry points nginx's reference
 * config allows (same regex), runs THAT script with SCRIPT_NAME,
 * SCRIPT_FILENAME, PHP_SELF and PATH_INFO set the way php-fpm would.
 * Everything else (front-controller paths like /login, /apps/files) falls
 * through to index.php untouched, as with `try_files ... /index.php$request_uri`.
 *
 * It also answers the two /.well-known redirects from Nextcloud's .htaccess.
 */
if (PHP_SAPI === 'cli' || !isset($_SERVER['REQUEST_URI'], $_SERVER['DOCUMENT_ROOT'], $_SERVER['SCRIPT_FILENAME'])) {
    return;
}

$__ephpm_target = (static function (): ?string {
    $path = rawurldecode((string) strtok($_SERVER['REQUEST_URI'], '?'));

    if (preg_match('#^/\.well-known/(?:carddav|caldav)(?:/|$)#', $path)) {
        header('Location: /remote.php/dav/', true, 301);
        exit;
    }

    // nginx: location ~ ^\/(?:index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|ocs-provider\/.+|.+\/richdocumentscode(_arm64)?\/proxy)\.php(?:$|\/)
    if (!preg_match('#^(/(?:index|remote|public|cron|core/ajax/update|status|ocs/v[12]|updater/[^/]+|ocs-provider/[^/]+|.+/richdocumentscode(?:_arm64)?/proxy)\.php)(/.*)?$#', $path, $m)) {
        return null;
    }
    $root = rtrim((string) realpath($_SERVER['DOCUMENT_ROOT']), '/');
    $file = realpath($root . $m[1]);
    if ($file === false || !is_file($file) || !str_starts_with($file, $root . '/')) {
        return null;
    }
    $info = $m[2] ?? '';
    $_SERVER['SCRIPT_NAME'] = $m[1];
    $_SERVER['PHP_SELF'] = $m[1] . $info;
    if ($info !== '') {
        $_SERVER['PATH_INFO'] = $info;
    }
    if ($file === realpath($_SERVER['SCRIPT_FILENAME'])) {
        return null;    // ePHPm is already running this script (e.g. /index.php/apps/files)
    }
    $_SERVER['SCRIPT_FILENAME'] = $file;
    return $file;
})();

if ($__ephpm_target !== null) {
    chdir(dirname($__ephpm_target));
    require $__ephpm_target;
    exit;
}
unset($__ephpm_target);
