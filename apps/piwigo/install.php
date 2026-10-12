<?php
// Unattended first-run install: drives Piwigo's own web installer
// (install.php in the web root) from the CLI with the PIWIGO_* variables,
// exactly as if its form had been submitted. Used by entrypoint.sh when
// PIWIGO_ADMIN_PASSWORD is set and local/config/database.inc.php is absent.
chdir('/var/www/html');
$env = static fn (string $k, string $d = ''): string => (string) (getenv($k) ?: $d);
$pass = $env('PIWIGO_ADMIN_PASSWORD');
$_GET = ['language' => $env('PIWIGO_LANGUAGE', 'en_UK')];
$_POST = [
    'install'     => 'Start installation',
    'dbhost'      => $env('PIWIGO_DB_HOST', 'db'),
    'dbuser'      => $env('PIWIGO_DB_USER', 'piwigo'),
    'dbpasswd'    => $env('PIWIGO_DB_PASSWORD'),
    'dbname'      => $env('PIWIGO_DB_NAME', 'piwigo'),
    'prefix'      => $env('PIWIGO_DB_PREFIX', 'piwigo_'),
    'admin_name'  => $env('PIWIGO_ADMIN_USER', 'admin'),
    'admin_pass1' => $pass,
    'admin_pass2' => $pass,
    'admin_mail'  => $env('PIWIGO_ADMIN_EMAIL', 'admin@example.com'),
    // no 'newsletter_subscribe': the installer only subscribes when it is set
];
ob_start();
require 'install.php';
ob_end_clean();
if (!empty($errors)) {
    fwrite(STDERR, "Piwigo installer errors:\n - " . implode("\n - ", array_map('strip_tags', $errors)) . "\n");
    exit(1);
}
echo "==> Piwigo installed (admin user: {$_POST['admin_name']})\n";
