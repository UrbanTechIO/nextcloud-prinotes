<?php

declare(strict_types=1);

namespace OCA\PriNotes\BackgroundJob;

use OCA\PriNotes\Db\Todo;
use OCA\PriNotes\Db\TodoMapper;
use OCA\PriNotes\Service\TodoService;
use OCP\AppFramework\Utility\ITimeFactory;
use OCP\BackgroundJob\TimedJob;
use OCP\Notification\IManager as INotificationManager;

class SendTodoRemindersJob extends TimedJob {
    public function __construct(
        ITimeFactory $time,
        private TodoMapper           $mapper,
        private TodoService          $todoService,
        private INotificationManager $notificationManager,
    ) {
        parent::__construct($time);
        $this->setInterval(60);
    }

    protected function run(mixed $argument): void {
        foreach ($this->mapper->findDueReminders(time()) as $todo) {
            try {
                $this->notify($todo);
            } finally {
                // Mark sent even if notifying failed, so one bad row cannot spam every minute.
                $this->todoService->markReminderSent($todo);
            }
        }
    }

    private function notify(Todo $todo): void {
        $n = $this->notificationManager->createNotification();
        $n->setApp('prinotes')
            ->setUser($todo->getUserId())
            ->setDateTime(new \DateTime())
            ->setObject('todo', (string)$todo->getId())
            ->setSubject('todo_reminder', ['todoId' => $todo->getId(), 'title' => $todo->getTitle()]);
        $this->notificationManager->notify($n);
    }
}
