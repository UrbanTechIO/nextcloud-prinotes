<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

use OCA\PriNotes\Db\Notebook;
use OCA\PriNotes\Db\NotebookMapper;

class NotebookService {
    public function __construct(private NotebookMapper $mapper) {}

    public function getAll(string $userId): array {
        return array_map(fn(Notebook $n) => $n->jsonSerialize(), $this->mapper->findAll($userId));
    }

    public function get(int $id, string $userId): array {
        return $this->mapper->findById($id, $userId)->jsonSerialize();
    }

    public function create(string $userId, array $data): array {
        $now = time();
        $nb = new Notebook();
        $nb->setUserId($userId);
        $nb->setTitle($data['title'] ?? 'New Notebook');
        $nb->setDescription($data['description'] ?? null);
        $nb->setColor($data['color'] ?? null);
        $nb->setIcon($data['icon'] ?? null);
        $nb->setSortOrder($data['sortOrder'] ?? 0);
        $nb->setCreatedAt($now);
        $nb->setUpdatedAt($now);
        return $this->mapper->insert($nb)->jsonSerialize();
    }

    public function update(int $id, string $userId, array $data): array {
        $nb = $this->mapper->findById($id, $userId);
        if (array_key_exists('title', $data))       $nb->setTitle($data['title']);
        if (array_key_exists('description', $data)) $nb->setDescription($data['description']);
        if (array_key_exists('color', $data))       $nb->setColor($data['color']);
        if (array_key_exists('icon', $data))        $nb->setIcon($data['icon']);
        if (array_key_exists('sortOrder', $data))   $nb->setSortOrder((int)$data['sortOrder']);
        $nb->setUpdatedAt(time());
        return $this->mapper->update($nb)->jsonSerialize();
    }

    public function delete(int $id, string $userId): void {
        $nb = $this->mapper->findById($id, $userId);
        $this->mapper->delete($nb);
    }
}
