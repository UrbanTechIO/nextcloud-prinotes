<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

use OCA\PriNotes\Db\Tag;
use OCA\PriNotes\Db\TagMapper;

class TagService {
    public function __construct(private TagMapper $mapper) {}

    public function getAll(string $userId): array {
        return array_map(fn(Tag $t) => $t->jsonSerialize(), $this->mapper->findAll($userId));
    }

    public function create(string $userId, array $data): array {
        $tag = new Tag();
        $tag->setUserId($userId);
        $tag->setName($data['name'] ?? 'Tag');
        $tag->setColor($data['color'] ?? null);
        $tag->setCreatedAt(time());
        return $this->mapper->insert($tag)->jsonSerialize();
    }

    public function update(int $id, string $userId, array $data): array {
        $tag = $this->mapper->findById($id, $userId);
        if (array_key_exists('name', $data))  $tag->setName($data['name']);
        if (array_key_exists('color', $data)) $tag->setColor($data['color']);
        return $this->mapper->update($tag)->jsonSerialize();
    }

    public function delete(int $id, string $userId): void {
        $tag = $this->mapper->findById($id, $userId);
        $this->mapper->delete($tag);
    }
}
