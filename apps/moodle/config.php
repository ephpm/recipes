<?php
// Moodle configuration for the ePHPm recipe — read from the environment, so
// the same image serves any deployment (see compose.yml for the variables).

unset($CFG);
global $CFG;
$CFG = new stdClass();

$CFG->dbtype    = getenv('MOODLE_DBTYPE') ?: 'pgsql';      // pgsql | mariadb | mysqli
$CFG->dblibrary = 'native';
$CFG->dbhost    = getenv('MOODLE_DBHOST') ?: 'db';
$CFG->dbname    = getenv('MOODLE_DBNAME') ?: 'moodle';
$CFG->dbuser    = getenv('MOODLE_DBUSER') ?: 'moodle';
$CFG->dbpass    = getenv('MOODLE_DBPASS') ?: '';
$CFG->prefix    = getenv('MOODLE_DBPREFIX') ?: 'mdl_';
$CFG->dboptions = [
    'dbpersist' => false,
    'dbsocket'  => false,
    'dbport'    => getenv('MOODLE_DBPORT') ?: '',
];
if ($CFG->dbtype !== 'pgsql') {
    $CFG->dboptions['dbcollation'] = 'utf8mb4_unicode_ci';
}

// The public URL, no trailing slash. Behind a TLS-terminating proxy set
// MOODLE_WWWROOT=https://... and MOODLE_SSLPROXY=true.
$CFG->wwwroot   = rtrim(getenv('MOODLE_WWWROOT') ?: 'http://localhost:8080', '/');
$CFG->sslproxy  = filter_var(getenv('MOODLE_SSLPROXY'), FILTER_VALIDATE_BOOLEAN);
$CFG->dataroot  = getenv('MOODLE_DATAROOT') ?: '/var/moodledata';
$CFG->admin     = 'admin';
$CFG->directorypermissions = 02777;

// ePHPm routes every URL that is not a file under public/ to r.php (the
// Moodle router), the setup Moodle calls "router configured".
$CFG->routerconfigured = true;
// ePHPm has no PATH_INFO, so file/theme/JS URLs must not use slash
// arguments (pluginfile.php/1/..., styles.php/boost/...): Moodle then
// generates ?file=... URLs instead.
$CFG->slasharguments = 0;

require_once(__DIR__ . '/lib/setup.php');
