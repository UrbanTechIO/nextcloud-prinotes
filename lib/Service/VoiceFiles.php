<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

/** Rules for voice recordings stored in the user's Nextcloud Files (PriNotes/voice). */
class VoiceFiles {
    public const MAX_BYTES = 50 * 1024 * 1024;

    /** Extension => mime type served back. The first mime of each extension is the one used for playback. */
    private const TYPES = [
        'm4a'  => 'audio/mp4',
        'aac'  => 'audio/aac',
        'webm' => 'audio/webm',
        'ogg'  => 'audio/ogg',
        'mp3'  => 'audio/mpeg',
    ];

    /** Other spellings of the same type that clients send. */
    private const ALIASES = [
        'audio/x-m4a'  => 'm4a',
        'audio/m4a'    => 'm4a',
        'audio/mp4a-latm' => 'm4a',
        'audio/x-aac'  => 'aac',
        'audio/opus'   => 'ogg',
        'audio/mp3'    => 'mp3',
    ];

    /** A recording id is made by the apps (a uuid, with or without dashes). Anything else is refused. */
    public static function validId(string $id): bool {
        return (bool)preg_match('/^[A-Za-z0-9-]{8,64}$/', $id);
    }

    /** File extension for an uploaded mime type, or null when it is not an audio type we keep. */
    public static function extensionFor(string $mime): ?string {
        $base = strtolower(trim(explode(';', $mime)[0]));
        foreach (self::TYPES as $ext => $type) {
            if ($base === $type) {
                return $ext;
            }
        }
        return self::ALIASES[$base] ?? null;
    }

    public static function mimeFor(string $extension): ?string {
        return self::TYPES[strtolower($extension)] ?? null;
    }

    /** An unused recording is only removed once it is this old (seconds), so one being added is never lost. */
    public const KEEP_SECONDS = 2 * 86400;

    /** The recording id from a stored file name ("<id>.m4a"), or null for anything else in the folder. */
    public static function idFromName(string $filename): ?string {
        $dot = strrpos($filename, '.');
        if ($dot === false) {
            return null;
        }
        $id  = substr($filename, 0, $dot);
        $ext = substr($filename, $dot + 1);
        if (!self::validId($id) || self::mimeFor($ext) === null) {
            return null;
        }
        return $id;
    }

    public static function isOldEnough(int $modifiedAt, int $now): bool {
        return $now - $modifiedAt > self::KEEP_SECONDS;
    }

    /** @return string[] */
    public static function extensions(): array {
        return array_keys(self::TYPES);
    }
}
