<?php

declare(strict_types=1);

namespace OCA\PriNotes\BackgroundJob;

use OCA\PriNotes\Db\Reminder;
use OCA\PriNotes\Service\ReminderService;
use OCP\AppFramework\Utility\ITimeFactory;
use OCP\BackgroundJob\TimedJob;
use OCP\Notification\IManager as INotificationManager;

class SendRemindersJob extends TimedJob {
    public function __construct(
        ITimeFactory $time,
        private ReminderService      $reminderService,
        private INotificationManager $notificationManager,
    ) {
        parent::__construct($time);
        $this->setInterval(60); // run every minute
    }

    protected function run(mixed $argument): void {
        $due = $this->reminderService->getDueReminders();

        foreach ($due as $reminder) {
            $this->sendNotification($reminder);
            $this->reminderService->markSent($reminder);
        }
    }

    private function sendNotification(Reminder $reminder): void {
        $notification = $this->notificationManager->createNotification();
        $notification->setApp('prinotes')
            ->setUser($reminder->getUserId())
            ->setDateTime(new \DateTime())
            ->setObject('reminder', (string)$reminder->getId())
            ->setSubject('reminder', [
                'noteId' => $reminder->getNoteId(),
            ]);
        $this->notificationManager->notify($notification);
    }
}
