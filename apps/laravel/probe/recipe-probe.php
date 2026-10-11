<?php
// Copied into public/ by test.sh for one request, then removed: boots the
// application and reads the user that artisan tinker inserted.
require __DIR__ . '/../vendor/autoload.php';
$app = require __DIR__ . '/../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
header('Content-Type: text/plain');
echo App\Models\User::query()->first()?->email ?? 'no-user';
