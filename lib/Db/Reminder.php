<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\Entity;

class Reminder extends Entity {
    protected int $noteId = 0;
    protected string $userId = '';
    protected int $remindAt = 0;
    protected int $isRecurring = 0;
    protected ?string $recurrenceRule = null;
    protected int $isSent = 0;
    protected int $createdAt = 0;

    public function jsonSerialize(): array {
        return [
            'id'             => $this->id,
            'noteId'         => $this->noteId,
            'remindAt'       => $this->remindAt,
            'isRecurring'    => (bool)$this->isRecurring,
            'recurrenceRule' => $this->recurrenceRule,
            'isSent'         => (bool)$this->isSent,
            'createdAt'      => $this->createdAt,
        ];
    }
}
