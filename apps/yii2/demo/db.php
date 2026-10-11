<?php
/**
 * config/db.php for the ePHPm recipe: connection from the environment
 * (DB_DSN, DB_USER, DB_PASSWORD) instead of the template's hard-coded DSN.
 */
return [
    'class' => \yii\db\Connection::class,
    'dsn' => getenv('DB_DSN') ?: 'mysql:host=127.0.0.1;port=3306;dbname=yii2basic',
    'username' => getenv('DB_USER') ?: 'root',
    'password' => getenv('DB_PASSWORD') ?: '',
    'charset' => 'utf8mb4',
    'enableSchemaCache' => true,
    'schemaCacheDuration' => 60,
    'schemaCache' => 'cache',
];
