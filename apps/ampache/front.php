<?php
// Fallback front controller: the rewrites Ampache ships as .htaccess.dist
// files that ePHPm's single `[server] fallback` chain cannot express
// (issues/espocrm.md: no per-prefix routing). Only the Subsonic API is
// mapped — `/rest/<action>.view` → `/rest/index.php?ssaction=<action>`
// (public/rest/.htaccess.dist), which every Subsonic client needs. Anything
// else is a 404, as with Apache and no matching file.
declare(strict_types=1);

$path = (string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);

if (preg_match('#^/rest/([^/]+?)(?:\.view)?/?$#', $path, $m)) {
    $_GET['ssaction'] = $m[1];
    $_SERVER['QUERY_STRING'] = http_build_query($_GET);
    $_SERVER['SCRIPT_NAME'] = $_SERVER['PHP_SELF'] = '/rest/index.php';
    $_SERVER['SCRIPT_FILENAME'] = __DIR__ . '/rest/index.php';
    chdir(__DIR__ . '/rest');
    require __DIR__ . '/rest/index.php';
    return;
}

http_response_code(404);
header('Content-Type: text/plain');
echo "Not Found\n";
