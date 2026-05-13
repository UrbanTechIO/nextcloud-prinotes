<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\Entity;

class Tag extends Entity {
    protected string $userId = '';
    protected string $name = '';
    protected ?string $color = null;
    protected int $createdAt = 0;

    public function jsonSerialize(): array {
        return [
            'id'        => $this->id,
            'name'      => $this->name,
            'color'     => $this->color,
            'createdAt' => $this->createdAt,
        ];
    }
}
