<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\Entity;

class Share extends Entity {
    protected int $noteId = 0;
    protected string $ownerId = '';
    // No non-null defaults on columns that are set explicitly: Entity::setter() skips
    // fields whose new value equals the current one, so a matching default would be
    // left out of the INSERT (NULL -> NOT NULL violation on PostgreSQL).
    protected ?string $shareType = null; // 'user' | 'public'
    protected ?string $sharedWith = null;
    protected ?string $token = null;
    protected ?string $permissions = null; // 'read' | 'write'
    protected int $createdAt = 0;

    public function jsonSerialize(): array {
        return [
            'id'          => $this->id,
            'noteId'      => $this->noteId,
            'shareType'   => $this->shareType,
            'sharedWith'  => $this->sharedWith,
            'token'       => $this->token,
            'permissions' => $this->permissions,
            'createdAt'   => $this->createdAt,
        ];
    }
}
