<?php
/**
 * phpMyAdmin configuration for the ePHPm recipe.
 *
 * Reads the same PMA_* environment variables as the official phpmyadmin
 * Docker image (and their *_FILE secret variants), so an existing compose
 * file's `environment:` block carries over unchanged. Modelled on
 * https://github.com/phpmyadmin/docker/blob/master/config.inc.php — the
 * multi-server PMA_HOSTS/PMA_PORTS/PMA_VERBOSES lists and the SSL options
 * (PMA_SSL*, PMA_SSL_*_BASE64) are supported the same way.
 */

declare(strict_types=1);

$pmaEnv = static function (string $name): ?string {
    $file = getenv($name . '_FILE');
    if (is_string($file) && $file !== '' && is_readable($file)) {
        return trim((string) file_get_contents($file));
    }
    $v = getenv($name);
    return $v === false ? null : $v;
};
$pmaList = static fn (?string $v): array => $v === null || $v === '' ? [] : array_map('trim', explode(',', $v));

/* Cookie encryption key: generated once by entrypoint.sh unless PMA_BLOWFISH_SECRET is set. */
$secretFile = '/etc/phpmyadmin/config.secret.inc.php';
if (is_file($secretFile)) {
    require_once $secretFile;
}
if (($s = $pmaEnv('PMA_BLOWFISH_SECRET')) !== null && $s !== '') {
    $cfg['blowfish_secret'] = $s;
}

/* Writable temp dir for templates/uploads (the official image uses ./tmp too). */
$cfg['TempDir'] = '/var/www/html/tmp';

if (($v = $pmaEnv('PMA_QUERYHISTORYDB')) !== null) {
    $cfg['QueryHistoryDB'] = (bool) $v;
}
if (($v = $pmaEnv('PMA_QUERYHISTORYMAX')) !== null) {
    $cfg['QueryHistoryMax'] = (int) $v;
}
if ($pmaEnv('PMA_ARBITRARY') === '1') {
    $cfg['AllowArbitraryServer'] = true;
}
if (($v = $pmaEnv('PMA_ABSOLUTE_URI')) !== null) {
    $cfg['PmaAbsoluteUri'] = trim($v);
}
if (($v = $pmaEnv('PMA_UPLOADDIR')) !== null) {
    $cfg['UploadDir'] = $v;
}
if (($v = $pmaEnv('PMA_SAVEDIR')) !== null) {
    $cfg['SaveDir'] = $v;
}
if (($v = $pmaEnv('MAX_EXECUTION_TIME')) !== null) {
    $cfg['ExecTimeLimit'] = (int) $v;
}
if (($v = $pmaEnv('MEMORY_LIMIT')) !== null) {
    $cfg['MemoryLimit'] = $v;
}

/* SSL material given as base64 is written next to the config (PMA_SSL_DIR). */
$sslDir = $pmaEnv('PMA_SSL_DIR') ?? '/etc/phpmyadmin/ssl';
$sslFromBase64 = static function (?string $b64, string $prefix, string $ext) use ($sslDir): ?string {
    if ($b64 === null || $b64 === '') {
        return null;
    }
    if (! is_dir($sslDir)) {
        mkdir($sslDir, 0755, true);
    }
    $paths = [];
    foreach (explode(',', $b64) as $i => $chunk) {
        $path = $sslDir . '/' . $prefix . '-' . $i . '.' . $ext;
        file_put_contents($path, base64_decode(trim($chunk)));
        $paths[] = $path;
    }
    return implode(',', $paths);
};
$sslCa   = $pmaEnv('PMA_SSL_CA')   ?? $sslFromBase64($pmaEnv('PMA_SSL_CA_BASE64'),   'ca',   'pem');
$sslKey  = $pmaEnv('PMA_SSL_KEY')  ?? $sslFromBase64($pmaEnv('PMA_SSL_KEY_BASE64'),  'key',  'key');
$sslCert = $pmaEnv('PMA_SSL_CERT') ?? $sslFromBase64($pmaEnv('PMA_SSL_CERT_BASE64'), 'cert', 'pem');
$sslCas   = $pmaEnv('PMA_SSL_CAS')   ?? $sslFromBase64($pmaEnv('PMA_SSL_CAS_BASE64'),   'ca',   'pem');
$sslKeys  = $pmaEnv('PMA_SSL_KEYS')  ?? $sslFromBase64($pmaEnv('PMA_SSL_KEYS_BASE64'),  'key',  'key');
$sslCerts = $pmaEnv('PMA_SSL_CERTS') ?? $sslFromBase64($pmaEnv('PMA_SSL_CERTS_BASE64'), 'cert', 'pem');

/* Servers: PMA_HOST (one) or PMA_HOSTS (comma-separated); default: the compose `db` service. */
if (($host = $pmaEnv('PMA_HOST')) !== null && $host !== '') {
    $hosts      = [$host];
    $verbose    = [$pmaEnv('PMA_VERBOSE')];
    $ports      = [$pmaEnv('PMA_PORT')];
    $ssls       = [$pmaEnv('PMA_SSL')];
    $sslVerify  = [$pmaEnv('PMA_SSL_VERIFY')];
    $sslCaList   = [$sslCa];
    $sslKeyList  = [$sslKey];
    $sslCertList = [$sslCert];
} elseif (($hostsEnv = $pmaEnv('PMA_HOSTS')) !== null && $hostsEnv !== '') {
    $hosts      = $pmaList($hostsEnv);
    $verbose    = $pmaList($pmaEnv('PMA_VERBOSES'));
    $ports      = $pmaList($pmaEnv('PMA_PORTS'));
    $ssls       = $pmaList($pmaEnv('PMA_SSLS'));
    $sslVerify  = $pmaList($pmaEnv('PMA_SSL_VERIFIES'));
    $sslCaList   = $pmaList($sslCas);
    $sslKeyList  = $pmaList($sslKeys);
    $sslCertList = $pmaList($sslCerts);
} else {
    $hosts = ['db'];
    $verbose = $ports = $ssls = $sslVerify = $sslCaList = $sslKeyList = $sslCertList = [];
}
$sockets = $pmaList($pmaEnv('PMA_SOCKET') ?? $pmaEnv('PMA_SOCKETS'));

$pmaUser = $pmaEnv('PMA_USER');
$pmaPassword = $pmaEnv('PMA_PASSWORD') ?? '';

for ($i = 1; isset($hosts[$i - 1]); $i++) {
    $cfg['Servers'][$i]['host'] = $hosts[$i - 1];
    if (! empty($verbose[$i - 1])) {
        $cfg['Servers'][$i]['verbose'] = $verbose[$i - 1];
    }
    if (! empty($ports[$i - 1])) {
        $cfg['Servers'][$i]['port'] = $ports[$i - 1];
    }
    if (($ssls[$i - 1] ?? null) === '1') {
        $cfg['Servers'][$i]['ssl'] = true;
    }
    if (($sslVerify[$i - 1] ?? null) === '1') {
        $cfg['Servers'][$i]['ssl_verify'] = true;
    }
    if (! empty($sslCaList[$i - 1])) {
        $cfg['Servers'][$i]['ssl_ca'] = $sslCaList[$i - 1];
    }
    if (! empty($sslKeyList[$i - 1])) {
        $cfg['Servers'][$i]['ssl_key'] = $sslKeyList[$i - 1];
    }
    if (! empty($sslCertList[$i - 1])) {
        $cfg['Servers'][$i]['ssl_cert'] = $sslCertList[$i - 1];
    }
    if ($pmaUser !== null && $pmaUser !== '') {
        // PMA_USER/PMA_PASSWORD: log in automatically with these credentials
        $cfg['Servers'][$i]['auth_type'] = 'config';
        $cfg['Servers'][$i]['user'] = $pmaUser;
        $cfg['Servers'][$i]['password'] = $pmaPassword;
    } else {
        $cfg['Servers'][$i]['auth_type'] = 'cookie';
    }
    if (($pmadb = $pmaEnv('PMA_PMADB')) !== null) {
        $cfg['Servers'][$i]['pmadb'] = $pmadb;
        foreach (['relation', 'table_info', 'table_coords', 'pdf_pages', 'column_info', 'history', 'recent', 'favorite',
            'table_uiprefs', 'tracking', 'userconfig', 'users', 'usergroups', 'navigationhiding', 'savedsearches',
            'central_columns', 'designer_settings', 'export_templates'] as $table) {
            $cfg['Servers'][$i][$table] = 'pma__' . $table;
        }
        $cfg['Servers'][$i]['bookmarktable'] = 'pma__bookmark';
    }
    foreach (['controlhost' => 'PMA_CONTROLHOST', 'controlport' => 'PMA_CONTROLPORT',
        'controluser' => 'PMA_CONTROLUSER', 'controlpass' => 'PMA_CONTROLPASS'] as $key => $env) {
        if (($v = $pmaEnv($env)) !== null) {
            $cfg['Servers'][$i][$key] = $v;
        }
    }
    $cfg['Servers'][$i]['compress'] = false;
    $cfg['Servers'][$i]['AllowNoPassword'] = true;
}
foreach ($sockets as $n => $socket) {
    $cfg['Servers'][$n + 1]['socket'] = $socket;
    $cfg['Servers'][$n + 1]['host'] = 'localhost';
}
$i--;

/* Local additions, as with the official image. */
if (is_file('/etc/phpmyadmin/config.user.inc.php')) {
    include '/etc/phpmyadmin/config.user.inc.php';
}
foreach (glob('/etc/phpmyadmin/conf.d/*.php') ?: [] as $filename) {
    include $filename;
}
