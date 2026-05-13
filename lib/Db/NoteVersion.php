<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\Entity;

class NoteVersion extends Entity {
    protected int $noteId = 0;
    protected string $userId = '';
    protected string $title = '';
    protected string $content = '{}';
    protected int $versionNumber = 1;
    protected int $createdAt = 0;

    public function jsonSerialize(): array {
        return [
            'id'            => $this->id,
            'noteId'        => $this->noteId,
            'title'         => $this->title,
            'versionNumber' => $this->versionNumber,
            'createdAt'     => $this->createdAt,
        ];
    }

    public function jsonSerializeWithContent(): array {
        return array_merge($this->jsonSerialize(), ['content' => $this->content]);
    }
}
