<?php

declare(strict_types=1);

require_once __DIR__ . '/../lib/Service/RepeatCalculator.php';

use OCA\PriNotes\Service\RepeatCalculator;

$failures = 0;
function check(string $name, mixed $actual, mixed $expected): void {
    global $failures;
    if ($actual !== $expected) {
        $failures++;
        echo "FAIL $name: expected " . var_export($expected, true) . ', got ' . var_export($actual, true) . "\n";
    }
}

check('monthly clamps Jan 31 to Feb 28', RepeatCalculator::nextDueDate('2026-01-31', 'monthly'), '2026-02-28');
check('monthly clamps Jan 31 to Feb 29 leap', RepeatCalculator::nextDueDate('2028-01-31', 'monthly'), '2028-02-29');
check('monthly keeps day', RepeatCalculator::nextDueDate('2026-03-15', 'monthly'), '2026-04-15');
check('monthly rolls year', RepeatCalculator::nextDueDate('2026-12-20', 'monthly'), '2027-01-20');
check('yearly leap day to Feb 28', RepeatCalculator::nextDueDate('2028-02-29', 'yearly'), '2029-02-28');
check('weekdays Friday to Monday', RepeatCalculator::nextDueDate('2026-11-06', 'weekdays'), '2026-11-09');
check('weekdays Saturday to Monday', RepeatCalculator::nextDueDate('2026-11-07', 'weekdays'), '2026-11-09');
check('weekdays Monday to Tuesday', RepeatCalculator::nextDueDate('2026-11-09', 'weekdays'), '2026-11-10');
check('weekly adds 7', RepeatCalculator::nextDueDate('2026-11-06', 'weekly'), '2026-11-13');
check('daily adds 1', RepeatCalculator::nextDueDate('2026-11-30', 'daily'), '2026-12-01');

$remind = gmmktime(18, 0, 0, 11, 6, 2026);
check('remindAt keeps time of day across shift',
    RepeatCalculator::nextRemindAt($remind, '2026-11-06', '2026-11-13'),
    gmmktime(18, 0, 0, 11, 13, 2026));
check('remindAt monthly clamp shift',
    RepeatCalculator::nextRemindAt(gmmktime(9, 30, 0, 1, 31, 2026), '2026-01-31', '2026-02-28'),
    gmmktime(9, 30, 0, 2, 28, 2026));

try {
    RepeatCalculator::nextDueDate('2026-11-06', 'fortnightly');
    $failures++;
    echo "FAIL unknown rule should throw\n";
} catch (InvalidArgumentException) {
}

try {
    RepeatCalculator::nextDueDate('not-a-date', 'daily');
    $failures++;
    echo "FAIL malformed date should throw\n";
} catch (InvalidArgumentException) {
}

if ($failures > 0) {
    echo "$failures failure(s)\n";
    exit(1);
}
echo "OK\n";
