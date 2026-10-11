<?php
/**
 * ePHPm front controller for EspoCRM.
 *
 * EspoCRM's Apache layout is: document root = the application root, and the
 * root .htaccess rewrites every request except /client/* into public/, where
 * public/api/v1/.htaccess and public/portal/.htaccess route /api/v1/* and
 * /portal/* to their own entry points (nginx users write a `location` block
 * for each). ePHPm has one `[server] fallback` chain for the whole site, so
 * this script is that fallback: static files (client/*) are served from the
 * application root directly, and everything else is dispatched here to the
 * entry point EspoCRM expects, with $_SERVER set the way Apache's rewrite
 * would set it — EspoCRM derives the API base path from SCRIPT_NAME
 * (Espo\Core\Utils\Route::detectBasePath).
 */

declare(strict_types=1);

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

// Apache rewrites pass the Authorization header on as this variable.
if (!isset($_SERVER['HTTP_ESPO_CGI_AUTH']) && isset($_SERVER['HTTP_AUTHORIZATION'])) {
    $_SERVER['HTTP_ESPO_CGI_AUTH'] = $_SERVER['HTTP_AUTHORIZATION'];
}

$entryPoints = [
    '/api/v1' => 'public/api/v1/index.php',
    '/portal' => 'public/portal/index.php',
];

$script = 'public/index.php';
foreach ($entryPoints as $prefix => $candidate) {
    if ($path === $prefix || str_starts_with($path, $prefix . '/')) {
        $script = $candidate;
        break;
    }
}

$file = __DIR__ . '/' . $script;
$_SERVER['SCRIPT_NAME'] = '/' . $script;
$_SERVER['PHP_SELF'] = '/' . $script;
$_SERVER['SCRIPT_FILENAME'] = $file;

// EspoCRM's entry points `require` bootstrap.php with a path relative to
// their own directory.
chdir(dirname($file));
require $file;
