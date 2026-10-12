<?php
/**
 * The official image's docker-init.php: after the schema is loaded, enable
 * the Users module and apply DOLI_COMPANY_NAME / DOLI_COMPANY_COUNTRYCODE /
 * DOLI_ENABLE_MODULES through Dolibarr's own API. Run from htdocs/.
 */

require_once 'master.inc.php';
require_once DOL_DOCUMENT_ROOT . '/core/lib/admin.lib.php';

printf("Activating module User... ");
activateModule('modUser');
printf("OK\n");

// The cron service runs scripts/cron/cron_run_jobs.php with this key (the
// official image sets CRON_KEY from DOLI_CRON_KEY the same way); the Cron
// module is enabled so there are scheduled jobs to run.
printf("Activating module Cron... ");
activateModule('modCron');
printf("OK\n");
if (!empty(getenv('DOLI_CRON_KEY'))) {
    dolibarr_set_const($db, 'CRON_KEY', getenv('DOLI_CRON_KEY'), 'chaine', 0, '', 0);
}

if (!empty(getenv('DOLI_COMPANY_COUNTRYCODE'))) {
    require_once DOL_DOCUMENT_ROOT . '/core/lib/company.lib.php';
    require_once DOL_DOCUMENT_ROOT . '/core/class/ccountry.class.php';
    $country = new Ccountry($db);
    if ($country->fetch(0, getenv('DOLI_COMPANY_COUNTRYCODE')) > 0) {
        $s = $country->id . ':' . $country->code . ':' . $country->label;
        dolibarr_set_const($db, 'MAIN_INFO_SOCIETE_COUNTRY', $s, 'chaine', 0, '', $conf->entity);
        printf("Configuring for country: %s\n", $s);
        activateModulesRequiredByCountry($country->code);
    } else {
        printf("Unable to find country %s\n", getenv('DOLI_COMPANY_COUNTRYCODE'));
    }
}

if (!empty(getenv('DOLI_COMPANY_NAME'))) {
    dolibarr_set_const($db, 'MAIN_INFO_SOCIETE_NOM', getenv('DOLI_COMPANY_NAME'), 'chaine', 0, '', $conf->entity);
}

if (!empty(getenv('DOLI_ENABLE_MODULES'))) {
    foreach (explode(',', getenv('DOLI_ENABLE_MODULES')) as $mod) {
        printf("Activating module %s ...", $mod);
        try {
            $res = activateModule('mod' . trim($mod));
            print(is_array($res) || $res >= 0 ? " OK\n" : " FAILED\n");
        } catch (Throwable $t) {
            print(" FAILED\n");
        }
    }
}
