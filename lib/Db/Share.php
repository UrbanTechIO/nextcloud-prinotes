<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\Entity;

class Share extends Entity {
    protected int $noteId = 0;
    protected string $ownerId = '';
    protected string $shareType = 'user'; // 'user' | 'public'
    protected ?string $sharedWith = null;
    protected ?string $token = null;
    protected string $permissions = 'read'; // 'read' | 'write'
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
