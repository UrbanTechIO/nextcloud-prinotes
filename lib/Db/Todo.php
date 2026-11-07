<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\Entity;

/**
 * @method string getUserId()
 * @method void setUserId(string $userId)
 * @method int getListId()
 * @method void setListId(int $listId)
 * @method string getTitle()
 * @method void setTitle(string $title)
 * @method string|null getNote()
 * @method void setNote(?string $note)
 * @method int getIsDone()
 * @method void setIsDone(int $isDone)
 * @method int|null getDoneAt()
 * @method void setDoneAt(?int $doneAt)
 * @method string|null getDueDate()
 * @method void setDueDate(?string $dueDate)
 * @method int|null getRemindAt()
 * @method void setRemindAt(?int $remindAt)
 * @method int getReminderSent()
 * @method void setReminderSent(int $reminderSent)
 * @method int getNextSpawned()
 * @method void setNextSpawned(int $nextSpawned)
 * @method string|null getRepeatRule()
 * @method void setRepeatRule(?string $repeatRule)
 * @method int getIsImportant()
 * @method void setIsImportant(int $isImportant)
 * @method string|null getSteps()
 * @method void setSteps(?string $steps)
 * @method int getSortOrder()
 * @method void setSortOrder(int $sortOrder)
 * @method int getCreatedAt()
 * @method void setCreatedAt(int $createdAt)
 * @method int getUpdatedAt()
 * @method void setUpdatedAt(int $updatedAt)
 * @method int getVersion()
 * @method void setVersion(int $version)
 */
class Todo extends Entity {
    protected string $userId = '';
    protected int $listId = 0;
    protected string $title = '';
    protected ?string $note = null;
    protected int $isDone = 0;
    protected ?int $doneAt = null;
    protected ?string $dueDate = null;
    protected ?int $remindAt = null;
    protected int $reminderSent = 0;
    protected int $nextSpawned = 0;
    protected ?string $repeatRule = null;
    protected int $isImportant = 0;
    protected ?string $steps = null;
    protected int $sortOrder = 0;
    protected int $createdAt = 0;
    protected int $updatedAt = 0;
    protected int $version = 1;

    /** Malformed steps JSON must never break a read: it becomes an empty list. */
    public function decodedSteps(): array {
        if ($this->steps === null || $this->steps === '') {
            return [];
        }
        $decoded = json_decode($this->steps, true);
        return is_array($decoded) ? array_values($decoded) : [];
    }

    public function jsonSerialize(): array {
        return [
            'id'           => $this->id,
            'listId'       => $this->listId,
            'title'        => $this->title,
            'note'         => $this->note,
            'isDone'       => $this->isDone === 1,
            'doneAt'       => $this->doneAt,
            'dueDate'      => $this->dueDate,
            'remindAt'     => $this->remindAt,
            'reminderSent' => $this->reminderSent === 1,
            'nextSpawned'  => $this->nextSpawned === 1,
            'repeatRule'   => $this->repeatRule,
            'isImportant'  => $this->isImportant === 1,
            'steps'        => $this->decodedSteps(),
            'sortOrder'    => $this->sortOrder,
            'createdAt'    => $this->createdAt,
            'updatedAt'    => $this->updatedAt,
            'version'      => $this->version,
        ];
    }
}
