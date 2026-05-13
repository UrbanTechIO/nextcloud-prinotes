<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

use OCA\PriNotes\Db\Reminder;
use OCA\PriNotes\Db\ReminderMapper;
use OCA\PriNotes\Db\NoteMapper;

class ReminderService {
    public function __construct(
        private ReminderMapper $reminderMapper,
        private NoteMapper     $noteMapper,
    ) {}

    public function getAll(string $userId): array {
        return array_map(
            fn(Reminder $r) => $r->jsonSerialize(),
            $this->reminderMapper->findAllForUser($userId)
        );
    }

    public function create(string $userId, array $data): array {
        $noteId = (int)($data['noteId'] ?? 0);
        $this->noteMapper->findById($noteId, $userId); // ownership check

        $r = new Reminder();
        $r->setNoteId($noteId);
        $r->setUserId($userId);
        $r->setRemindAt((int)($data['remindAt'] ?? 0));
        $r->setIsRecurring((int)(bool)($data['isRecurring'] ?? false));
        $r->setRecurrenceRule($data['recurrenceRule'] ?? null);
        $r->setIsSent(0);
        $r->setCreatedAt(time());

        return $this->reminderMapper->insert($r)->jsonSerialize();
    }

    public function update(int $id, string $userId, array $data): array {
        $r = $this->reminderMapper->findById($id, $userId);
        if (array_key_exists('remindAt', $data))       $r->setRemindAt((int)$data['remindAt']);
        if (array_key_exists('isRecurring', $data))    $r->setIsRecurring((int)(bool)$data['isRecurring']);
        if (array_key_exists('recurrenceRule', $data)) $r->setRecurrenceRule($data['recurrenceRule']);
        if (array_key_exists('isSent', $data))         $r->setIsSent((int)(bool)$data['isSent']);
        return $this->reminderMapper->update($r)->jsonSerialize();
    }

    public function delete(int $id, string $userId): void {
        $r = $this->reminderMapper->findById($id, $userId);
        $this->reminderMapper->delete($r);
    }

    public function getDueReminders(): array {
        return $this->reminderMapper->findDue(time());
    }

    public function markSent(Reminder $reminder): void {
        $reminder->setIsSent(1);
        if ($reminder->getIsRecurring() && $reminder->getRecurrenceRule()) {
            $next = $this->calculateNextOccurrence($reminder->getRemindAt(), $reminder->getRecurrenceRule());
            if ($next) {
                $reminder->setRemindAt($next);
                $reminder->setIsSent(0);
            }
        }
        $this->reminderMapper->update($reminder);
    }

    private function calculateNextOccurrence(int $timestamp, string $rule): ?int {
        // Supports: daily, weekly, monthly
        return match ($rule) {
            'daily'   => $timestamp + 86400,
            'weekly'  => $timestamp + 604800,
            'monthly' => strtotime('+1 month', $timestamp),
            default   => null,
        };
    }
}
