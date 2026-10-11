<?php
/**
 * user/config.php for the ePHPm recipe.
 *
 * Reads the same YOURLS_* environment variables (and *_FILE secrets) as the
 * official yourls Docker image's config-container.php, so an existing compose
 * file's `environment:` block carries over unchanged. The cookie key not
 * given in the environment is generated once by entrypoint.sh and kept in
 * the user/ volume (user/cookiekey.txt).
 */

if (!function_exists('getenv_container')) {
    function getenv_container(string $name, ?string $default = null): ?string
    {
        if ($fileEnv = getenv($name . '_FILE')) {
            return trim((string) file_get_contents($fileEnv));
        }
        if (($value = getenv($name)) !== false) {
            return $value;
        }
        return $default;
    }
}

/*
 ** MySQL settings
 */
define( 'YOURLS_DB_USER', getenv_container('YOURLS_DB_USER', 'root') );
define( 'YOURLS_DB_PASS', getenv_container('YOURLS_DB_PASS', '') );
define( 'YOURLS_DB_NAME', getenv_container('YOURLS_DB_NAME', 'yourls') );
/** 'hostname' or 'hostname:port' (the compose file's `db` service). */
define( 'YOURLS_DB_HOST', getenv_container('YOURLS_DB_HOST', 'db') );
define( 'YOURLS_DB_PREFIX', getenv_container('YOURLS_DB_PREFIX', 'yourls_') );

/*
 ** Site options
 */
/** Public URL of this instance, no trailing slash — REQUIRED. */
define( 'YOURLS_SITE', rtrim((string) getenv_container('YOURLS_SITE', 'http://localhost:8080'), '/') );
define( 'YOURLS_HOURS_OFFSET', filter_var(getenv('YOURLS_HOURS_OFFSET'), FILTER_VALIDATE_INT) ?: 0 );
define( 'YOURLS_LANG', getenv('YOURLS_LANG') ?: '' );
define( 'YOURLS_UNIQUE_URLS', getenv('YOURLS_UNIQUE_URLS') === false ?: filter_var(getenv('YOURLS_UNIQUE_URLS'), FILTER_VALIDATE_BOOLEAN) );
define( 'YOURLS_PRIVATE', getenv('YOURLS_PRIVATE') === false ?: filter_var(getenv('YOURLS_PRIVATE'), FILTER_VALIDATE_BOOLEAN) );

/** Cookie encryption key: YOURLS_COOKIEKEY, else the one entrypoint.sh generated into the user/ volume. */
$ephpm_cookiekey = getenv('YOURLS_COOKIEKEY') ?: @file_get_contents(__DIR__ . '/cookiekey.txt');
define( 'YOURLS_COOKIEKEY', is_string($ephpm_cookiekey) && trim($ephpm_cookiekey) !== '' ? trim($ephpm_cookiekey) : 'modify this text with something random' );

/** Admin user(s): YOURLS_USER / YOURLS_PASS (plain text; YOURLS hashes them in this file on first login). */
$yourls_user_passwords = [
    getenv_container('YOURLS_USER', 'admin') => getenv_container('YOURLS_PASS', ''),
];

define( 'YOURLS_URL_CONVERT', filter_var(getenv('YOURLS_URL_CONVERT'), FILTER_VALIDATE_INT) ?: 36 );
define( 'YOURLS_DEBUG', filter_var(getenv('YOURLS_DEBUG'), FILTER_VALIDATE_BOOLEAN) );
define( 'YOURLS_NO_VERSION_CHECK', getenv('YOURLS_NO_VERSION_CHECK') === false ?: filter_var(getenv('YOURLS_NO_VERSION_CHECK'), FILTER_VALIDATE_BOOLEAN) );
define( 'YOURLS_NOSTATS', filter_var(getenv('YOURLS_NOSTATS'), FILTER_VALIDATE_BOOLEAN) );

/** Reserved keywords (generated short URLs never match them). */
$yourls_reserved_URL = [
    'porn', 'faggot', 'sex', 'nigger', 'fuck', 'cunt', 'dick',
];
