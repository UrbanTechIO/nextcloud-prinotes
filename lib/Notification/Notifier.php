<?php

declare(strict_types=1);

namespace OCA\PriNotes\Notification;

use OCP\IURLGenerator;
use OCP\Notification\INotification;
use OCP\Notification\INotifier;

/** Renders To-Do reminders only. Any other PriNotes notification is left untouched. */
class Notifier implements INotifier {
    public function __construct(private IURLGenerator $urlGenerator) {}

    public function getID(): string {
        return 'prinotes';
    }

    public function getName(): string {
        return 'PriNotes';
    }

    public function prepare(INotification $notification, string $languageCode): INotification {
        if ($notification->getApp() !== 'prinotes' || $notification->getSubject() !== 'todo_reminder') {
            throw self::unknown();
        }
        $params = $notification->getSubjectParameters();
        $title = (string)($params['title'] ?? '');
        $notification->setParsedSubject('Reminder: ' . $title);
        $notification->setLink($this->urlGenerator->linkToRouteAbsolute('prinotes.page.index') . '#/todo');
        $notification->setIcon($this->urlGenerator->getAbsoluteURL($this->urlGenerator->imagePath('prinotes', 'app.svg')));
        return $notification;
    }

    private static function unknown(): \Throwable {
        $cls = '\OCP\Notification\UnknownNotificationException';
        return class_exists($cls) ? new $cls() : new \InvalidArgumentException();
    }
}
