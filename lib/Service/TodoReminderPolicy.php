<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

/**
 * Decides whether the server should also push a To-Do reminder through Nextcloud notifications.
 * To-Do reminders come from the PriNotes Android app itself; the Nextcloud notification is an extra the user
 * has to switch on.
 */
class TodoReminderPolicy {
    /** The user setting `todo_nextcloud_reminders` is 'true' only when the user switched the extra notification on. */
    public static function sendNextcloudNotification(?string $setting): bool {
        return in_array(strtolower(trim((string)$setting)), ['true', '1'], true);
    }
}
