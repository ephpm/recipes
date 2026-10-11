<?php
/**
 * Nextcloud config fragment for the ePHPm recipe (config/ephpm.config.php,
 * merged over config.php by Nextcloud, like the official image's
 * apcu/apps/reverse-proxy fragments). Rewritten from the image on every
 * start: change the environment, not this file.
 */
$CONFIG = [
    // APCu from ePHPm's extension catalog (loaded by [php] extensions).
    'memcache.local' => '\OC\Memcache\APCu',

    // Bundled apps stay in the image; apps installed from the app store go
    // to the custom_apps volume — the same layout as the official image.
    'apps_paths' => [
        ['path' => OC::$SERVERROOT . '/apps', 'url' => '/apps', 'writable' => false],
        ['path' => OC::$SERVERROOT . '/custom_apps', 'url' => '/custom_apps', 'writable' => true],
    ],

    // ePHPm routes every non-file path to index.php (its `fallback`), which is
    // what Apache's .htaccess front-controller rules do; tell Nextcloud so it
    // generates /apps/files instead of /index.php/apps/files.
    'htaccess.RewriteBase' => '/',
    'htaccess.IgnoreFrontController' => true,
];

// Host names the instance answers to (NEXTCLOUD_TRUSTED_DOMAINS, space-separated).
if (getenv('NEXTCLOUD_TRUSTED_DOMAINS')) {
    $CONFIG['trusted_domains'] = array_values(array_filter(explode(' ', getenv('NEXTCLOUD_TRUSTED_DOMAINS'))));
}
// Behind a TLS-terminating proxy — same variables as the official image.
if (getenv('OVERWRITEPROTOCOL')) {
    $CONFIG['overwriteprotocol'] = getenv('OVERWRITEPROTOCOL');
}
if (getenv('OVERWRITEHOST')) {
    $CONFIG['overwritehost'] = getenv('OVERWRITEHOST');
}
if (getenv('OVERWRITECLIURL')) {
    $CONFIG['overwrite.cli.url'] = getenv('OVERWRITECLIURL');
}
if (getenv('TRUSTED_PROXIES')) {
    $CONFIG['trusted_proxies'] = array_values(array_filter(explode(' ', getenv('TRUSTED_PROXIES'))));
}
