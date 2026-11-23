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

check('no setting yet: PriNotes only', TodoReminderPolicy::sendNextcloudNotification(null), false);
check('empty string: PriNotes only', TodoReminderPolicy::sendNextcloudNotification(''), false);
check('explicit false', TodoReminderPolicy::sendNextcloudNotification('false'), false);
check('garbage is off', TodoReminderPolicy::sendNextcloudNotification('maybe'), false);
check('explicit true: the user asked for the extra notification', TodoReminderPolicy::sendNextcloudNotification('true'), true);
check('1 means on', TodoReminderPolicy::sendNextcloudNotification('1'), true);
check('TRUE any case', TodoReminderPolicy::sendNextcloudNotification('TRUE'), true);

echo $failures === 0 ? "OK\n" : "$failures failure(s)\n";
exit($failures === 0 ? 0 : 1);
