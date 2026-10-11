<?php

namespace App\Database\Migrations;

use CodeIgniter\Database\Migration;

/**
 * Recipe demo: a guestbook table so the smoke test can write and read a
 * record through HTTP. Delete together with Controllers/Guestbook.php.
 */
class CreateGuestbook extends Migration
{
    public function up(): void
    {
        $this->forge->addField([
            'id'         => ['type' => 'INT', 'unsigned' => true, 'auto_increment' => true],
            'name'       => ['type' => 'VARCHAR', 'constraint' => 100],
            'message'    => ['type' => 'TEXT'],
            'created_at' => ['type' => 'DATETIME', 'null' => true],
        ]);
        $this->forge->addKey('id', true);
        $this->forge->createTable('guestbook');
    }

    public function down(): void
    {
        $this->forge->dropTable('guestbook');
    }
}
