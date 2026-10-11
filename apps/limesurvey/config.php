<?php if (!defined('BASEPATH')) exit('No direct script access allowed');
/*
 * application/config/config.php for the ePHPm recipe — read from the
 * environment (the variable names of the widely used martialblog/limesurvey
 * image), so the same image serves any deployment.
 */
$ephpmEnv = static function (string $name, string $default = ''): string {
    $file = getenv($name . '_FILE');
    if ($file !== false && $file !== '' && is_readable($file)) {
        return trim((string) file_get_contents($file));
    }
    $value = getenv($name);
    return $value === false ? $default : $value;
};
$dbType = $ephpmEnv('DB_TYPE', 'mysql');

return array(
    'components' => array(
        'db' => array(
            'connectionString' => sprintf('%s:host=%s;port=%s;dbname=%s;', $dbType,
                $ephpmEnv('DB_HOST', 'db'), $ephpmEnv('DB_PORT', $dbType === 'pgsql' ? '5432' : '3306'),
                $ephpmEnv('DB_NAME', 'limesurvey')),
            'emulatePrepare' => true,
            'username' => $ephpmEnv('DB_USERNAME', 'limesurvey'),
            'password' => $ephpmEnv('DB_PASSWORD'),
            'charset' => $ephpmEnv('DB_CHARSET', $dbType === 'pgsql' ? 'utf8' : 'utf8mb4'),
            'tablePrefix' => $ephpmEnv('DB_TABLE_PREFIX', 'lime_'),
        ),
        // Path URLs (/index.php/admin/...) — required by the REST API and the
        // new editor. ePHPm has no PATH_INFO, but Yii derives the route from
        // REQUEST_URI, and [server] fallback sends /admin/... to index.php.
        'urlManager' => array(
            'urlFormat' => $ephpmEnv('URL_FORMAT', 'path'),
            'rules' => array(),
            'showScriptName' => filter_var($ephpmEnv('SHOW_SCRIPT_NAME', 'true'), FILTER_VALIDATE_BOOLEAN),
        ),
    ),
    'config' => array(
        'publicurl' => $ephpmEnv('PUBLIC_URL'),
        'debug' => (int) $ephpmEnv('DEBUG', '0'),
        'debugsql' => (int) $ephpmEnv('DEBUG_SQL', '0'),
        'mysqlEngine' => $ephpmEnv('DB_MYSQL_ENGINE', 'InnoDB'),
    ),
);
