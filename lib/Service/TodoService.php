<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

use InvalidArgumentException;
use OCA\PriNotes\Db\Todo;
use OCA\PriNotes\Db\TodoListMapper;
use OCA\PriNotes\Db\TodoMapper;
use OCP\AppFramework\Db\DoesNotExistException;

class TodoService {
    public function __construct(
        private TodoMapper      $mapper,
        private TodoListMapper  $listMapper,
        private TodoListService $listService,
    ) {}

    public function getAll(string $userId): array {
        return array_map(fn(Todo $t) => $t->jsonSerialize(), $this->mapper->findAll($userId));
    }

    public function getUpdatedSince(string $userId, int $since): array {
        return array_map(fn(Todo $t) => $t->jsonSerialize(), $this->mapper->findUpdatedSince($userId, $since));
    }

    public function getAllIds(string $userId): array {
        return $this->mapper->findAllIds($userId);
    }

    public function get(int $id, string $userId): array {
        return $this->mapper->findById($id, $userId)->jsonSerialize();
    }

    public function create(string $userId, array $data): array {
        $now = time();
        $todo = new Todo();
        $todo->setUserId($userId);
        $todo->setListId($this->resolveListId($userId, $data['listId'] ?? null));
        $todo->setTitle($this->cleanTitle($data['title'] ?? ''));
        $todo->setNote($data['note'] ?? null);
        $todo->setIsDone(!empty($data['isDone']) ? 1 : 0);
        $todo->setDoneAt(!empty($data['isDone']) ? $now : null);
        $todo->setDueDate($this->cleanDate($data['dueDate'] ?? null));
        $todo->setRemindAt(isset($data['remindAt']) ? (int)$data['remindAt'] : null);
        $todo->setRepeatRule($this->cleanRule($data['repeatRule'] ?? null));
        $todo->setIsImportant(!empty($data['isImportant']) ? 1 : 0);
        $todo->setSteps($this->cleanSteps($data['steps'] ?? []));
        $todo->setSortOrder((int)($data['sortOrder'] ?? 0));
        $todo->setCreatedAt($now);
        $todo->setUpdatedAt($now);
        $out = $this->mapper->insert($todo)->jsonSerialize();
        if (isset($data['clientId'])) {
            $out['clientId'] = $data['clientId'];
        }
        return $out;
    }

    public function update(int $id, string $userId, array $data): array {
        $todo = $this->mapper->findById($id, $userId);

        // A client built from an older copy must not overwrite newer server data.
        if (isset($data['version']) && (int)$data['version'] < $todo->getVersion()) {
            $out = $todo->jsonSerialize();
            if (isset($data['clientId'])) {
                $out['clientId'] = $data['clientId'];
            }
            return $out;
        }

        $wasDone = $todo->getIsDone() === 1;
        $oldRemind = $todo->getRemindAt();

        if (array_key_exists('listId', $data))     $todo->setListId($this->resolveListId($userId, $data['listId']));
        if (array_key_exists('title', $data))      $todo->setTitle($this->cleanTitle($data['title']));
        if (array_key_exists('note', $data))       $todo->setNote($data['note']);
        if (array_key_exists('dueDate', $data))    $todo->setDueDate($this->cleanDate($data['dueDate']));
        if (array_key_exists('remindAt', $data))   $todo->setRemindAt($data['remindAt'] === null ? null : (int)$data['remindAt']);
        if (array_key_exists('repeatRule', $data)) $todo->setRepeatRule($this->cleanRule($data['repeatRule']));
        if (array_key_exists('isImportant', $data)) $todo->setIsImportant(!empty($data['isImportant']) ? 1 : 0);
        if (array_key_exists('steps', $data))      $todo->setSteps($this->cleanSteps($data['steps']));
        if (array_key_exists('sortOrder', $data))  $todo->setSortOrder((int)$data['sortOrder']);
        if (array_key_exists('isDone', $data))     $todo->setIsDone(!empty($data['isDone']) ? 1 : 0);

        $isDone = $todo->getIsDone() === 1;
        $now = time();
        if ($isDone && !$wasDone) {
            $todo->setDoneAt($now);
        } elseif (!$isDone && $wasDone) {
            $todo->setDoneAt(null);
        }
        if ($todo->getRemindAt() !== $oldRemind || (!$isDone && $wasDone)) {
            $todo->setReminderSent(0);
        }

        $spawn = $isDone && !$wasDone && $todo->getRepeatRule() !== null && $todo->getNextSpawned() === 0;
        if ($spawn) {
            $todo->setNextSpawned(1);
        }
        $todo->setVersion($todo->getVersion() + 1);
        $todo->setUpdatedAt($now);
        $saved = $this->mapper->update($todo);

        if ($spawn) {
            $this->spawnNext($saved);
        }

        $out = $saved->jsonSerialize();
        if (isset($data['clientId'])) {
            $out['clientId'] = $data['clientId'];
        }
        return $out;
    }

    public function delete(int $id, string $userId): void {
        $this->mapper->delete($this->mapper->findById($id, $userId));
    }

    public function markReminderSent(Todo $todo): void {
        $todo->setReminderSent(1);
        $this->mapper->update($todo);
    }

    /** Creates the next occurrence of a just-completed repeating task. */
    private function spawnNext(Todo $done): void {
        $oldDue = $done->getDueDate() ?? gmdate('Y-m-d');
        $newDue = RepeatCalculator::nextDueDate($oldDue, (string)$done->getRepeatRule());

        $now = time();
        $next = new Todo();
        $next->setUserId($done->getUserId());
        $next->setListId($done->getListId());
        $next->setTitle($done->getTitle());
        $next->setNote($done->getNote());
        $next->setDueDate($newDue);
        $remind = $done->getRemindAt();
        $next->setRemindAt($remind === null ? null : RepeatCalculator::nextRemindAt($remind, $oldDue, $newDue));
        $next->setRepeatRule($done->getRepeatRule());
        $next->setIsImportant($done->getIsImportant());
        $steps = array_map(fn($s) => ['id' => $s['id'] ?? uniqid('s'), 'text' => $s['text'] ?? '', 'done' => false], $done->decodedSteps());
        $next->setSteps(json_encode($steps));
        $next->setSortOrder($done->getSortOrder());
        $next->setCreatedAt($now);
        $next->setUpdatedAt($now);
        $this->mapper->insert($next);
    }

    /** Unknown or missing list: re-home into the Inbox instead of failing. */
    private function resolveListId(string $userId, mixed $listId): int {
        if ($listId !== null && $listId !== '' && (int)$listId > 0) {
            try {
                return $this->listMapper->findById((int)$listId, $userId)->getId();
            } catch (DoesNotExistException) {
            }
        }
        return $this->listService->getInbox($userId)->getId();
    }

    private function cleanTitle(mixed $title): string {
        $title = trim((string)$title);
        if ($title === '') {
            throw new InvalidArgumentException('Title required');
        }
        return mb_substr($title, 0, 500);
    }

    private function cleanDate(mixed $date): ?string {
        if ($date === null || $date === '') {
            return null;
        }
        $date = (string)$date;
        $parsed = \DateTimeImmutable::createFromFormat('!Y-m-d', $date);
        if ($parsed === false || $parsed->format('Y-m-d') !== $date) {
            throw new InvalidArgumentException('dueDate must be YYYY-MM-DD');
        }
        return $date;
    }

    private function cleanRule(mixed $rule): ?string {
        if ($rule === null || $rule === '') {
            return null;
        }
        if (!in_array($rule, RepeatCalculator::RULES, true)) {
            throw new InvalidArgumentException('Unknown repeat rule');
        }
        return $rule;
    }

    private function cleanSteps(mixed $steps): string {
        if (is_string($steps)) {
            $steps = json_decode($steps, true);
        }
        if (!is_array($steps)) {
            return '[]';
        }
        $clean = [];
        foreach (array_slice($steps, 0, 100) as $s) {
            if (!is_array($s)) {
                continue;
            }
            $text = mb_substr(trim((string)($s['text'] ?? '')), 0, 500);
            if ($text === '') {
                continue;
            }
            $clean[] = ['id' => (string)($s['id'] ?? uniqid('s')), 'text' => $text, 'done' => !empty($s['done'])];
        }
        return json_encode($clean);
    }
}
