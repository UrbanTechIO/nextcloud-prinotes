<?php

declare(strict_types=1);

require_once __DIR__ . '/../lib/Service/VoiceFiles.php';

use OCA\PriNotes\Service\VoiceFiles;

$failures = 0;
function check(string $name, mixed $actual, mixed $expected): void {
    global $failures;
    if ($actual !== $expected) {
        $failures++;
        echo "FAIL $name: expected " . var_export($expected, true) . ', got ' . var_export($actual, true) . "\n";
    }
}

// Recording ids are made by the apps (a uuid); anything else could point outside the folder.
check('uuid ok', VoiceFiles::validId('3f2b8c1e-9a4d-4e57-8b21-0c6d5a7e9f10'), true);
check('hex ok', VoiceFiles::validId('3f2b8c1e9a4d4e578b210c6d5a7e9f10'), true);
check('empty', VoiceFiles::validId(''), false);
check('path tricks', VoiceFiles::validId('../../etc/passwd'), false);
check('slash', VoiceFiles::validId('abc/def'), false);
check('dot', VoiceFiles::validId('abc.mp3'), false);
check('too long', VoiceFiles::validId(str_repeat('a', 65)), false);
check('too short', VoiceFiles::validId('abc'), false);

// Mime <-> extension
check('m4a mime', VoiceFiles::extensionFor('audio/mp4'), 'm4a');
check('aac mime', VoiceFiles::extensionFor('audio/aac'), 'aac');
check('webm mime', VoiceFiles::extensionFor('audio/webm'), 'webm');
check('webm with codec', VoiceFiles::extensionFor('audio/webm;codecs=opus'), 'webm');
check('ogg mime', VoiceFiles::extensionFor('audio/ogg'), 'ogg');
check('mp3 mime', VoiceFiles::extensionFor('audio/mpeg'), 'mp3');
check('x-m4a mime', VoiceFiles::extensionFor('audio/x-m4a'), 'm4a');
check('not audio', VoiceFiles::extensionFor('image/png'), null);
check('script', VoiceFiles::extensionFor('text/html'), null);
check('empty mime', VoiceFiles::extensionFor(''), null);

check('m4a back', VoiceFiles::mimeFor('m4a'), 'audio/mp4');
check('webm back', VoiceFiles::mimeFor('webm'), 'audio/webm');
check('unknown back', VoiceFiles::mimeFor('exe'), null);

check('all extensions', VoiceFiles::extensions(), ['m4a', 'aac', 'webm', 'ogg', 'mp3']);
check('size limit is 50 MB', VoiceFiles::MAX_BYTES, 50 * 1024 * 1024);

// Clean-up of recordings no note uses any more
check('id from a stored file name', VoiceFiles::idFromName('3f2b8c1e-9a4d-4e57-8b21-0c6d5a7e9f10.m4a'), '3f2b8c1e-9a4d-4e57-8b21-0c6d5a7e9f10');
check('id from a web recording', VoiceFiles::idFromName('3f2b8c1e-9a4d-4e57-8b21-0c6d5a7e9f10.webm'), '3f2b8c1e-9a4d-4e57-8b21-0c6d5a7e9f10');
check('other files in the folder are left alone', VoiceFiles::idFromName('holiday.txt'), null);
check('no ending', VoiceFiles::idFromName('3f2b8c1e-9a4d-4e57-8b21-0c6d5a7e9f10'), null);
check('bad id', VoiceFiles::idFromName('../x.m4a'), null);
check('a fresh file is never removed', VoiceFiles::isOldEnough(1000, 1000 + 3600), false);
check('a day old is still kept', VoiceFiles::isOldEnough(1000, 1000 + 86400), false);
check('after two days an unused one may go', VoiceFiles::isOldEnough(1000, 1000 + 2 * 86400 + 1), true);

echo $failures === 0 ? "OK\n" : "$failures failure(s)\n";
exit($failures === 0 ? 0 : 1);
