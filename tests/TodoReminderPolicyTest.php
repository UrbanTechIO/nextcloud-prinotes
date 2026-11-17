<?php

declare(strict_types=1);

require_once __DIR__ . '/../lib/Service/TodoReminderPolicy.php';

use OCA\PriNotes\Service\TodoReminderPolicy;

$failures = 0;
function check(string $name, mixed $actual, mixed $expected): void {
    global $failures;
    if ($actual !== $expected) {
        $failures++;
        echo "FAIL $name: expected " . var_export($expected, true) . ', got ' . var_export($actual, true) . "\n";
    }
}

check('no setting yet: keep sending (web-only users)', TodoReminderPolicy::sendNextcloudNotification(null), true);
check('explicit true', TodoReminderPolicy::sendNextcloudNotification('true'), true);
check('explicit false: the Android app handles reminders', TodoReminderPolicy::sendNextcloudNotification('false'), false);
check('0 means off', TodoReminderPolicy::sendNextcloudNotification('0'), false);
check('FALSE any case', TodoReminderPolicy::sendNextcloudNotification('FALSE'), false);
check('garbage keeps sending', TodoReminderPolicy::sendNextcloudNotification('maybe'), true);
check('empty string keeps sending', TodoReminderPolicy::sendNextcloudNotification(''), true);

echo $failures === 0 ? "OK\n" : "$failures failure(s)\n";
exit($failures === 0 ? 0 : 1);
