<?php
declare(strict_types=1);

namespace App\Controller;

use Cake\Http\Response;

/**
 * Recipe demo: GET /guestbook lists entries as JSON (and exposes the CSRF
 * token the skeleton's CsrfProtectionMiddleware expects), POST /guestbook
 * (name, message, X-CSRF-Token header) adds one. Delete with the migration.
 */
class GuestbookController extends AppController
{
    public function index(): Response
    {
        $table = $this->fetchTable('Guestbook');
        $rows = $table->find()->orderByDesc('id')->all()->toList();

        return $this->response->withType('application/json')->withStringBody(json_encode([
            'csrfToken' => $this->request->getAttribute('csrfToken'),
            'entries' => $rows,
        ], JSON_UNESCAPED_SLASHES));
    }

    public function add(): Response
    {
        $this->request->allowMethod(['post']);
        $table = $this->fetchTable('Guestbook');
        $entity = $table->newEntity([
            'name' => (string)$this->request->getData('name'),
            'message' => (string)$this->request->getData('message'),
            'created' => date('Y-m-d H:i:s'),
        ]);
        if ($entity->name === '' || $entity->message === '' || !$table->save($entity)) {
            return $this->response->withStatus(422)->withType('application/json')
                ->withStringBody(json_encode(['error' => 'name and message are required']));
        }

        return $this->response->withStatus(201)->withType('application/json')
            ->withStringBody(json_encode(['id' => $entity->id]));
    }
}
