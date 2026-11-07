<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

use InvalidArgumentException;
use OCA\PriNotes\Db\TodoList;
use OCA\PriNotes\Db\TodoListMapper;
use OCA\PriNotes\Db\TodoMapper;

class TodoListService {
    public function __construct(
        private TodoListMapper $mapper,
        private TodoMapper     $todoMapper,
    ) {}

    public function getInbox(string $userId): TodoList {
        $inbox = $this->mapper->findInbox($userId);
        if ($inbox !== null) {
            return $inbox;
        }
        $now = time();
        $list = new TodoList();
        $list->setUserId($userId);
        $list->setTitle('Inbox');
        $list->setIsSystem(1);
        $list->setSystemKey('inbox');
        $list->setCreatedAt($now);
        $list->setUpdatedAt($now);
        try {
            return $this->mapper->insert($list);
        } catch (\Throwable $e) {
            // Two devices created it at once: the unique (user_id, system_key) index rejected the loser.
            $existing = $this->mapper->findInbox($userId);
            if ($existing !== null) {
                return $existing;
            }
            throw $e;
        }
    }

    public function getAll(string $userId): array {
        $this->getInbox($userId);
        return array_map(fn(TodoList $l) => $l->jsonSerialize(), $this->mapper->findAll($userId));
    }

    public function create(string $userId, array $data): array {
        $title = $this->cleanTitle($data['title'] ?? '');
        $parentId = $this->validParent($userId, $data['parentId'] ?? null, null);

        $now = time();
        $list = new TodoList();
        $list->setUserId($userId);
        $list->setParentId($parentId);
        $list->setTitle($title);
        $list->setColor($data['color'] ?? null);
        $list->setSortOrder((int)($data['sortOrder'] ?? 0));
        $list->setCreatedAt($now);
        $list->setUpdatedAt($now);
        $out = $this->mapper->insert($list)->jsonSerialize();
        if (isset($data['clientId'])) {
            $out['clientId'] = $data['clientId'];
        }
        return $out;
    }

    public function update(int $id, string $userId, array $data): array {
        $list = $this->mapper->findById($id, $userId);
        if ($list->getIsSystem() === 1) {
            if (array_key_exists('title', $data) || array_key_exists('parentId', $data)) {
                throw new InvalidArgumentException('The Inbox cannot be renamed or moved');
            }
        }
        if (array_key_exists('title', $data)) {
            $list->setTitle($this->cleanTitle($data['title']));
        }
        if (array_key_exists('parentId', $data)) {
            $list->setParentId($this->validParent($userId, $data['parentId'], $id));
        }
        if (array_key_exists('color', $data)) {
            $list->setColor($data['color']);
        }
        if (array_key_exists('sortOrder', $data)) {
            $list->setSortOrder((int)$data['sortOrder']);
        }
        $list->setUpdatedAt(time());
        $out = $this->mapper->update($list)->jsonSerialize();
        if (isset($data['clientId'])) {
            $out['clientId'] = $data['clientId'];
        }
        return $out;
    }

    /** Deletes the list, its sub-lists and every task in them. */
    public function delete(int $id, string $userId): void {
        $list = $this->mapper->findById($id, $userId);
        if ($list->getIsSystem() === 1) {
            throw new InvalidArgumentException('The Inbox cannot be deleted');
        }
        foreach ($this->mapper->findChildren($id, $userId) as $child) {
            $this->todoMapper->deleteByList($child->getId(), $userId);
            $this->mapper->delete($child);
        }
        $this->todoMapper->deleteByList($id, $userId);
        $this->mapper->delete($list);
    }

    private function cleanTitle(mixed $title): string {
        $title = trim((string)$title);
        if ($title === '') {
            throw new InvalidArgumentException('Title required');
        }
        return mb_substr($title, 0, 255);
    }

    /** One level of nesting only: the parent must exist, be top level, not the Inbox, and not be this list's child. */
    private function validParent(string $userId, mixed $parentId, ?int $selfId): ?int {
        if ($parentId === null || $parentId === '' || (int)$parentId === 0) {
            return null;
        }
        $parentId = (int)$parentId;
        if ($selfId !== null) {
            if ($parentId === $selfId) {
                throw new InvalidArgumentException('A list cannot be its own parent');
            }
            if (count($this->mapper->findChildren($selfId, $userId)) > 0) {
                throw new InvalidArgumentException('A list with sub-lists cannot become a sub-list');
            }
        }
        $parent = $this->mapper->findById($parentId, $userId);
        if ($parent->getParentId() !== null || $parent->getIsSystem() === 1) {
            throw new InvalidArgumentException('Sub-lists can only be one level deep');
        }
        return $parentId;
    }
}
