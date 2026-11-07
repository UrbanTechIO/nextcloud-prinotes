<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

use DateTimeImmutable;
use DateTimeZone;
use InvalidArgumentException;

class RepeatCalculator {
    public const RULES = ['daily', 'weekdays', 'weekly', 'monthly', 'yearly'];

    public static function nextDueDate(string $dueDate, string $rule): string {
        $date = DateTimeImmutable::createFromFormat('!Y-m-d', $dueDate, new DateTimeZone('UTC'));
        if ($date === false || $date->format('Y-m-d') !== $dueDate) {
            throw new InvalidArgumentException("Invalid due date: $dueDate");
        }

        $next = match ($rule) {
            'daily'    => $date->modify('+1 day'),
            'weekly'   => $date->modify('+7 days'),
            'weekdays' => self::nextWeekday($date),
            'monthly'  => self::addMonthsClamped($date, 1),
            'yearly'   => self::addMonthsClamped($date, 12),
            default    => throw new InvalidArgumentException("Unknown repeat rule: $rule"),
        };
        return $next->format('Y-m-d');
    }

    /** Shift a reminder by the same whole-day distance as the due date, keeping its time of day. */
    public static function nextRemindAt(int $remindAt, string $oldDue, string $newDue): int {
        $old = new DateTimeImmutable($oldDue, new DateTimeZone('UTC'));
        $new = new DateTimeImmutable($newDue, new DateTimeZone('UTC'));
        $days = (int)$old->diff($new)->format('%r%a');
        return $remindAt + $days * 86400;
    }

    private static function nextWeekday(DateTimeImmutable $date): DateTimeImmutable {
        do {
            $date = $date->modify('+1 day');
        } while ((int)$date->format('N') >= 6);
        return $date;
    }

    private static function addMonthsClamped(DateTimeImmutable $date, int $months): DateTimeImmutable {
        $day = (int)$date->format('j');
        $firstOfTarget = $date->modify('first day of this month')->modify("+$months months");
        $lastDay = (int)$firstOfTarget->format('t');
        return $firstOfTarget->setDate(
            (int)$firstOfTarget->format('Y'),
            (int)$firstOfTarget->format('n'),
            min($day, $lastDay),
        );
    }
}
