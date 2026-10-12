<?php
// Unattended first-run install: writes config_si.php from the SUITECRM_*
// variables and runs install.php's SilentInstall path from the CLI, the way
// upstream documents (`install.php?goto=SilentInstall&cli=true`).
// Used by entrypoint.sh when config.php is not installer-locked yet.
chdir('/var/www/html');
$e = static fn (string $k, string $d = ''): string => (string) (getenv($k) ?: $d);

$si = [
    'setup_site_url'                      => $e('SUITECRM_SITE_URL', 'http://localhost:8080'),
    'setup_system_name'                   => $e('SUITECRM_SYSTEM_NAME', 'SuiteCRM'),
    'setup_site_admin_user_name'          => $e('SUITECRM_ADMIN_USER', 'admin'),
    'setup_site_admin_password'           => $e('SUITECRM_ADMIN_PASSWORD'),
    'setup_db_type'                       => 'mysql',
    'setup_db_host_name'                  => $e('SUITECRM_DB_HOST', 'db'),
    'setup_db_port_num'                   => $e('SUITECRM_DB_PORT', '3306'),
    'setup_db_database_name'              => $e('SUITECRM_DB_NAME', 'suitecrm'),
    'setup_db_admin_user_name'            => $e('SUITECRM_DB_USER', 'suitecrm'),
    'setup_db_admin_password'             => $e('SUITECRM_DB_PASSWORD'),
    'setup_db_sugarsales_user'            => $e('SUITECRM_DB_USER', 'suitecrm'),
    'setup_db_sugarsales_password'        => $e('SUITECRM_DB_PASSWORD'),
    'dbUSRData'                           => 'same',
    'setup_db_create_database'            => 0,
    'setup_db_create_sugarsales_user'     => false,
    'setup_db_drop_tables'                => 0,
    'setup_db_pop_demo_data'              => false,
    'demoData'                            => 'no',
    'default_language'                    => $e('SUITECRM_LANGUAGE', 'en_us'),
    'default_currency_iso4217'            => $e('SUITECRM_CURRENCY_ISO4217', 'USD'),
    'default_currency_name'               => $e('SUITECRM_CURRENCY_NAME', 'US Dollars'),
    'default_currency_symbol'             => $e('SUITECRM_CURRENCY_SYMBOL', '$'),
    'default_currency_significant_digits' => 2,
    'default_date_format'                 => $e('SUITECRM_DATE_FORMAT', 'Y-m-d'),
    'default_time_format'                 => $e('SUITECRM_TIME_FORMAT', 'H:i'),
    'default_decimal_seperator'           => '.',
    'default_number_grouping_seperator'   => ',',
    'default_export_charset'              => 'UTF-8',
    'default_locale_name_format'          => 's f l',
    'export_delimiter'                    => ',',
];
if ($si['setup_site_admin_password'] === '') {
    fwrite(STDERR, "!!! SUITECRM_ADMIN_PASSWORD is required for the first start\n");
    exit(1);
}
file_put_contents('config_si.php', "<?php\n\$sugar_config_si = " . var_export($si, true) . ";\n");

$u = parse_url($si['setup_site_url']);
$_SERVER['HTTP_HOST']   = $u['host'] . (isset($u['port']) ? ':' . $u['port'] : '');
$_SERVER['SERVER_NAME'] = $u['host'];
$_SERVER['SERVER_PORT'] = (string) ($u['port'] ?? 80);
$_SERVER['REQUEST_URI'] = '/install.php?goto=SilentInstall&cli=true';
$_SERVER['SCRIPT_NAME'] = '/install.php';
$_SERVER['PHP_SELF']    = '/install.php';
$_REQUEST = $_GET = ['goto' => 'SilentInstall', 'cli' => 'true'];
register_shutdown_function(static function (): void { @unlink('/var/www/html/config_si.php'); });
require 'install.php';
