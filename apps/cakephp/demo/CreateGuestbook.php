<?php
declare(strict_types=1);

use Migrations\BaseMigration;

/**
 * Recipe demo: a guestbook table so the smoke test can write and read a
 * record through HTTP. Delete together with Controller/GuestbookController.php.
 */
class CreateGuestbook extends BaseMigration
{
    public function change(): void
    {
        $this->table('guestbook')
            ->addColumn('name', 'string', ['limit' => 100])
            ->addColumn('message', 'text')
            ->addColumn('created', 'datetime', ['null' => true])
            ->create();
    }
}
