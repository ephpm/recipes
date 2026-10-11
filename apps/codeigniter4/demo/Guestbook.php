<?php

namespace App\Controllers;

use CodeIgniter\HTTP\ResponseInterface;

/**
 * Recipe demo: GET /guestbook lists entries as JSON, POST /guestbook
 * (name, message) adds one. Delete together with the migration.
 */
class Guestbook extends BaseController
{
    public function index(): ResponseInterface
    {
        $rows = $this->db()->table('guestbook')->orderBy('id', 'DESC')->get()->getResultArray();

        return $this->response->setJSON(['entries' => $rows]);
    }

    public function create(): ResponseInterface
    {
        $name    = trim((string) $this->request->getPost('name'));
        $message = trim((string) $this->request->getPost('message'));
        if ($name === '' || $message === '') {
            return $this->response->setStatusCode(422)->setJSON(['error' => 'name and message are required']);
        }
        $this->db()->table('guestbook')->insert([
            'name'       => $name,
            'message'    => $message,
            'created_at' => date('Y-m-d H:i:s'),
        ]);

        return $this->response->setStatusCode(201)->setJSON(['id' => $this->db()->insertID()]);
    }

    private function db(): \CodeIgniter\Database\BaseConnection
    {
        return \Config\Database::connect();
    }
}
