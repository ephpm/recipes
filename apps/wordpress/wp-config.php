<?php
/**
 * wp-config.php for the ePHPm recipe.
 *
 * Reads the same WORDPRESS_* environment variables the official WordPress
 * Docker image uses, so an existing compose file's `environment:` block
 * carries over unchanged. Defaults point at ePHPm's embedded database
 * (litewire MySQL frontend on 127.0.0.1:3306) for the single-container
 * variant.
 */

$env = static function (string $name, string $default = ''): string {
    $v = getenv($name);
    return $v === false ? $default : $v;
};

define('DB_NAME',     $env('WORDPRESS_DB_NAME', 'wordpress'));
define('DB_USER',     $env('WORDPRESS_DB_USER', 'root'));
define('DB_PASSWORD', $env('WORDPRESS_DB_PASSWORD', ''));
define('DB_HOST',     $env('WORDPRESS_DB_HOST', '127.0.0.1:3306'));
define('DB_CHARSET',  $env('WORDPRESS_DB_CHARSET', 'utf8mb4'));
define('DB_COLLATE',  '');

$table_prefix = $env('WORDPRESS_TABLE_PREFIX', 'wp_');

// Salts: WORDPRESS_AUTH_KEY etc. from the environment, otherwise a set
// generated once by entrypoint.sh and persisted in the wp-content volume.
$salts = [
    'AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY',
    'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT',
];
$saltFile = __DIR__ . '/wp-content/ephpm-salts.php';
$generated = is_file($saltFile) ? (include $saltFile) : [];
foreach ($salts as $k) {
    $v = $env('WORDPRESS_' . $k);
    if ($v === '' && isset($generated[$k])) {
        $v = $generated[$k];
    }
    define($k, $v === '' ? 'put your unique phrase here' : $v);
}

// Persistent object cache: wp-content/object-cache.php (ephpm/cache-wordpress)
// talks to ePHPm's in-process KV store via ephpm_kv_*. No Redis.
define('WP_CACHE', true);

define('WP_DEBUG', filter_var($env('WORDPRESS_DEBUG', '0'), FILTER_VALIDATE_BOOLEAN));
define('WP_DEBUG_DISPLAY', false);
define('WP_DEBUG_LOG', '/dev/stderr');

// Plugin/theme/core updates write straight to the filesystem (no FTP prompt).
define('FS_METHOD', 'direct');

// Trust X-Forwarded-Proto from a TLS-terminating proxy in front of ePHPm.
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}

if (($extra = $env('WORDPRESS_CONFIG_EXTRA')) !== '') {
    eval($extra);
}

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}
require_once ABSPATH . 'wp-settings.php';
