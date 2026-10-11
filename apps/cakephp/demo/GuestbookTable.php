<?php
declare(strict_types=1);

namespace App\Model\Table;

use Cake\ORM\Table;

/**
 * Recipe demo: ORM table class for the guestbook (CakePHP 5 does not fall
 * back to a generic Table class). Delete with the migration and controller.
 */
class GuestbookTable extends Table
{
    public function initialize(array $config): void
    {
        parent::initialize($config);
        $this->setTable('guestbook');
        $this->setPrimaryKey('id');
    }
}
