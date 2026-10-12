<?php
// First start: replace the installer's default `administrator` / `root`
// account credentials with MANTIS_ADMIN_USER / MANTIS_ADMIN_PASSWORD /
// MANTIS_ADMIN_EMAIL through MantisBT's own user API.
chdir('/app');
require_once 'core.php';
require_api('user_api.php');

$name = getenv('MANTIS_ADMIN_USER') ?: 'administrator';
$pass = getenv('MANTIS_ADMIN_PASSWORD') ?: '';
$mail = getenv('MANTIS_ADMIN_EMAIL') ?: '';

$id = user_get_id_by_name('administrator');
if ($id === false) {
    fwrite(STDERR, "no 'administrator' account to update\n");
    exit(1);
}
if ($name !== 'administrator') {
    user_set_name($id, $name);
}
if ($pass !== '') {
    user_set_password($id, $pass);
} else {
    fwrite(STDERR, "MANTIS_ADMIN_PASSWORD not set: the administrator password stays 'root' — change it now\n");
}
if ($mail !== '') {
    user_set_email($id, $mail);
}
echo "==> administrator account: {$name}\n";
