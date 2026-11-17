<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

/** Decides whether the server should also push a To-Do reminder through Nextcloud notifications. */
class TodoReminderPolicy {
    /** The user setting `todo_nextcloud_notifications` is 'false' when the Android app shows reminders itself. */
    public static function sendNextcloudNotification(?string $setting): bool {
        return !in_array(strtolower(trim((string)$setting)), ['false', '0'], true);
    }
}
