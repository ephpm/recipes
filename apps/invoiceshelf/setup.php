<?php
// Unattended first-run setup: what InvoiceShelf's web installation wizard
// does after its database step (which is `migrate --seed`, run by
// entrypoint.sh): turn the seeded placeholder account
// (admin@invoiceshelf.com / invoiceshelf@123, company "xyz") into the
// configured administrator and company, and mark the wizard complete.
chdir('/app');
require 'vendor/autoload.php';
$app = require 'bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$e = static fn (string $k, string $d = ''): string => (string) (getenv($k) ?: $d);

$user = App\Models\User::where('role', 'super admin')->firstOrFail();
$user->email = $e('INVOICESHELF_ADMIN_EMAIL', 'admin@example.com');
$user->name = $e('INVOICESHELF_ADMIN_NAME', 'Admin');
$user->password = $e('INVOICESHELF_ADMIN_PASSWORD'); // hashed by User::setPasswordAttribute
$user->save();

$company = $user->companies()->first();
$company->name = $e('INVOICESHELF_COMPANY_NAME', 'My Company');
$company->slug = Illuminate\Support\Str::slug($company->name) ?: 'company';
$company->save();

App\Models\Setting::setSetting('profile_complete', 'COMPLETED');
echo "==> InvoiceShelf set up: {$user->email} / company \"{$company->name}\"\n";
