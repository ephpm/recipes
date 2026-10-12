<?php
/**
 * ePHPm front controller for PrestaShop (the `[server] fallback` target).
 *
 * PrestaShop has three front controllers: the shop (`/index.php`), the back
 * office (`/<admin folder>/index.php`, a Symfony app whose routes look like
 * `/<admin>/index.php/sell/catalog/products`) and the Admin API
 * (`/admin-api/index.php`). Apache reaches the back-office routes through
 * `AcceptPathInfo`; ePHPm has neither PATH_INFO nor per-prefix fallbacks
 * (issues/espocrm.md), so a request for a path that is not a file lands
 * here, and this script picks the entry point by prefix, sets
 * SCRIPT_NAME / SCRIPT_FILENAME / PHP_SELF the way php-fpm would for that
 * script (Symfony derives the route from REQUEST_URI minus SCRIPT_NAME),
 * and runs it.
 */

declare(strict_types=1);

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

$script = '/index.php';
$admin = getenv('PS_FOLDER_ADMIN') ?: 'admin';
foreach (['/' . $admin . '/', '/admin-api/'] as $prefix) {
    if (str_starts_with($path, $prefix)) {
        $script = $prefix . 'index.php';
        break;
    }
}

$pathInfo = '';
if (str_starts_with($path, $script . '/')) {
    $pathInfo = substr($path, strlen($script));
}

$_SERVER['SCRIPT_NAME'] = $script;
$_SERVER['PHP_SELF'] = $script . $pathInfo;
$_SERVER['SCRIPT_FILENAME'] = __DIR__ . $script;
if ($pathInfo !== '') {
    $_SERVER['PATH_INFO'] = $pathInfo;
}

chdir(dirname(__DIR__ . $script));
require __DIR__ . $script;
