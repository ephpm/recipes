<?php
/**
 * ePHPm front controller for OJS.
 *
 * OJS builds its request path from $_SERVER['SCRIPT_NAME'] + $_SERVER['PATH_INFO']
 * (PKPRequest::getRequestPath). Under Apache, `AcceptPathInfo On` plus the
 * rewrite `^(.*)$ index.php/$1` hands every URL to index.php with the rest of
 * the path in PATH_INFO. ePHPm has no PATH_INFO support (issues/espocrm.md), so
 * this script — the `[server] fallback` target — reconstructs it from the
 * request URI, for both URL styles OJS can generate (`/index.php/journal/...`
 * and, with `restful_urls = On`, `/journal/...`), then runs index.php.
 */

declare(strict_types=1);

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
if ($path === '/index.php' || str_starts_with($path, '/index.php/')) {
    $path = substr($path, strlen('/index.php'));
}
if ($path === '') {
    $path = '/';
}

$_SERVER['PATH_INFO'] = $path;
$_SERVER['SCRIPT_NAME'] = '/index.php';
$_SERVER['PHP_SELF'] = '/index.php' . $path;
$_SERVER['SCRIPT_FILENAME'] = __DIR__ . '/index.php';

chdir(__DIR__);
require __DIR__ . '/index.php';
