# Changelog

All notable changes to PriNotes are documented here.

## [1.2.8] – 2026-11-23

Web app and Android app. Needs the Nextcloud app update (new recording storage and a changed reminder setting).

### Added
- **Voice notes.** Attach, then Voice, records a voice note and puts it in the note at the cursor. Add as many as you like, between your text.
  - The recorder shows live sound waves while you speak, with Pause, Cancel and Add to note. It stops by itself after 30 minutes.
  - In the note a recording is a player: play and pause, its sound waves with the played part coloured (tap or drag the waves to jump), a name you can change (tap it), its length, and a remove button. Only one plays at a time.
  - **Hold a recording and drag it** up or down to move it between lines (Android and web). On the web a line shows where it will land.
  - Works offline: recordings are kept on the phone and upload when there is a connection. Recordings made elsewhere download on their own, or with the Download button.
  - The audio is stored as files in your own Nextcloud Files, in `PriNotes/voice`. A daily job removes recordings no note uses any more (only ones older than two days).
  - **Web:** the same players, and a microphone button on the toolbar records in the browser.
  - Recordings made before the sound waves existed show a flat row of bars.
- **Scan text with the camera (Android).** Attach, then Scan, turns the bottom half of the screen into a camera.
  - **Live:** point at printed text and each new line floats up into the note. A line is added only after it was read the same way three times in a row, and only text inside the frame is read.
  - **Snap:** take one photo, check or edit the text it found, then Insert. The photo is not kept.
  - Reads Latin text only (no Arabic). Works offline.

### Changed
- **To-Do reminders come from PriNotes only.** The extra Nextcloud notification is now off unless you turn it on (Settings, Reminders, *Also notify through Nextcloud*). Other Nextcloud notifications are not affected. The server setting was renamed (`todo_nextcloud_reminders`), so an old saved choice no longer counts.
- A reminder set on the web or on another phone now gets its alarm on the phone right after the next sync, not up to 15 minutes later.
- Pictures from the camera and gallery are shrunk to at most 1600 pixels when added, so notes stay small and quick.
- The side menu in Frosted Glass is lighter to draw, so it opens smoother.

### Fixed
- Portrait pictures were stretched into a wide frame. They keep their own shape now.
- Pictures: the resize handles and the red delete button only worked on their inner half, and touching a picture opened the keyboard. Both work properly now, and a selected picture stays selected until you tap outside.
- Pictures were slow to appear because the full photo was decoded again on every touch.
- The side menu could lag right after opening the app.
- Web: playing a recording failed with "Could not play" because Nextcloud blocks sound from temporary browser addresses. It now plays straight from the server.

## [1.2.7] – 2026-11-19

Web app and Android app.

### Added
- **Trash count.** The number of notes in the trash is shown next to Trash in the web side menu, and as a badge on the Trash icon in the Android sidebars (Notes and To-Do). Nothing is shown when the trash is empty. It updates when you trash, restore or permanently delete a note.

## [1.2.6] – 2026-11-19

Web app and Android app. The Nextcloud app (store) version moves from 1.2.3 to 1.2.6 and now also carries the reminder switch from 1.2.5.

### Added
- **Web: drawing with real lines.** The ✎ button on the editor toolbar now draws freehand on the page, with pen, eraser, colour, size, Undo, Clear and Done. Drawings are saved as the same lines the phone saves, so a drawing made on either side opens and edits on the other. Before, the web drew a picture that was pasted into the note.
- **Web: drawings from the phone are shown.** They were hidden by the editor and were wiped when a note was saved on the web. They now show, scroll with the text, and survive saving.
- **Web: font size and text style pickers** match the phone: sizes 12, 15, 18, 22 and 28, labelled boxes in the same height as the other toolbar buttons, and the theme's colours.
- **Android: the pen starts white on a dark theme** (and black on a light one) instead of always black.
- The note records the page width the drawing was made on (`strokesWidth`), so the web can place the drawing correctly.

### Changed
- Ink that cannot be seen on the page's own colours (white on a light page, black on a dark one) is shown in the page's text colour on the web. The saved colour is not changed.
- Web: the pen starts in the page's text colour, so a stroke is visible on the dark and the light theme.

### Fixed
- Text sizes written on the phone ("28") did nothing in the web, and sizes set on the web ("28px") did not show on the phone. Both apps now read and write the same form.
- Server: the "Also notify through Nextcloud" switch from the Android app (1.2.5) now takes effect.

## [1.2.5] – 2026-11-17

Android app. The Nextcloud app (web) store version stays at 1.2.3; the reminder switch below needs a matching Nextcloud app update, which comes with the next web release.

### Added
- **Update check.** PriNotes looks for a newer release on GitHub each time it starts, and offers it with the release notes. Settings → Updates → **Check for updates** does the same on demand. Tap **Download and install** and Android's installer takes it from there (Android asks once to allow PriNotes to install apps). "Later" is remembered for that version.
- **New sidebars** for notes and To-Do: a Notes / To-Do switch at the top, Today / Important / Planned / All tasks as tiles with counts, categories as plain one-line rows (sub-categories fold under their parent), tags as chips, and a bottom bar with Archive, Trash, Settings and Lock. Long-press a category, notebook or tag for Edit, Add sub-category or Delete. The width follows the screen (80%, between 272 and 320 dp), and on short screens the bottom bar scrolls with the list.
- **Reminders from PriNotes only.** Settings → Reminders → *Also notify through Nextcloud*. To-Do reminders always come from PriNotes itself; turn the switch off to stop the extra notification in the Nextcloud app (takes effect once the Nextcloud app is updated).

### Changed
- Tapping a reminder notification opens the To-Do page on that task's category.

### Fixed
- Tapping a task in the home-screen widget opened the notes list instead of To-Do, especially when the app was locked. It now opens the To-Do page on the task's category, also after unlocking with a fingerprint or PIN.

## [1.2.4] – 2026-11-15

Android app only. The Nextcloud app (web) stays at 1.2.3.

### Added
- **Backgrounds for the glass themes:** seven built-in backgrounds and "Add photo" for your own picture (Settings → Appearance → Background).
- **Widget transparency:** a "Background opacity" slider in the To-Do widget settings (tap the widget title).
- **To-Do remembers the last list.** Tapping To-Do opens the list you left it on, also after closing the app.
- A 📝 mark on a task that has a note, next to its due date and reminder.
- The phone vibrates when you select the first note.
- The sidebar now follows the theme: the same frosted pane as the header in Frosted Glass, a floating glass panel in Liquid Glass, with a see-through account header.

### Changed
- The plus button in Frosted Glass looks exactly like the header and follows the same opacity slider.
- Note cards in landscape are no longer huge: they are at most 240 wide, so landscape shows more columns.
- Settings shows the real app version.
- Glass themes use much less memory: note and To-Do cards no longer run a blur each (about 600 MB of graphics memory before, against 284 MB in Classic). Android had been closing the app in the background for low memory.

### Fixed
- Leaving a note with the phone's back button or gesture did not save it.
- Back with notes selected closed the app instead of clearing the selection.
- "Move to trash" in a note's menu did nothing: the confirmation never appeared, and on short screens the row was cut off. The menu now scrolls.
- The header sat under the status bar on phones that show one (issue #4). The app now checks whether the status bar is visible: header below it when shown, at the top when hidden.
- The Classic theme header was not at the top on phones that hide the status bar.
- Opening Settings or going back drew the old and new screen on top of each other in the glass themes.
- The sidebar menus could not scroll in landscape.

## [1.2.3] – 2026-11-07

### Added
- **Undo and Redo** buttons in the note editor (web and Android). They step through typing, deleting, formatting and added or removed images. Android keeps 100 steps and the web 200; edits typed within about half a second merge into one step.
- **Save on an interval instead of on every edit.** A note is saved at most 60 seconds after its first unsaved change, and right away when you leave the editor, the app goes to the background, or the browser tab is hidden or closed. The editor shows "Unsaved" or "Saved", and has a Save now button (Ctrl+S on the web).
- A note that ends up identical to its last saved version (for example text typed and then undone) is not rewritten, so its modified time and its place in the list do not change.

- **Android: Theme setting** with Classic (default), Frosted Glass and Liquid Glass. The glass themes apply to notes, To-Do, the side menus and Settings, with sliders for header and card opacity.
- **Android: backgrounds for the glass themes.** Seven built-in backgrounds (Aurora, Sunset, Forest, Ocean, Rose, Ember, Graphite) and "Add photo" to use your own picture.
- Android: the search bar is now an icon in the header that slides open over the other icons.
- Android: new app icon.

### Changed
- Android: Settings now shows the real app version.

### Fixed
- Android: opening Settings or going back drew the old and new screen on top of each other for a moment in the glass themes.
- Android: the release build could crash at start-up (reminder boot receiver, minified build).
- Sync: when the server could not read To-Do data, `/api/sync/pull` returned an empty category list, which made the Android app delete all its local categories. It now returns `null` ("unknown") and clients keep what they have.
- Sync: a task added to a category that was created offline was filed under Inbox. The push now carries the new category's `clientId` and the server maps it to the created category.

## [1.2.1] – 2026-11-07

### Added
- **To-Do lists** (web and Android), in the side menu above Trash. Categories with sub-categories, smart lists (Today, Important, Planned, All tasks), due dates, reminders, repeating tasks (daily, weekdays, weekly, monthly, yearly), steps, notes and a star for important tasks. Finished tasks collapse into a "Finished" group under the same category.
- To-Dos use the same sync as notes (`/api/sync/pull` and `/api/sync/push`), so web and phone stay in step. The server creates the next occurrence of a repeating task when it is completed.
- Reminders: Nextcloud notification from a background job (every minute), and local alarms with Done / Snooze actions on Android.
- Android home-screen widgets (medium and large) that show to-dos from any mix of lists, let you tick tasks and add new ones.
- Android: bulk select (long-press), bulk finish and bulk delete with Undo, and a compact "Add a task" bar like Microsoft To-Do.

### Changed
- Database: two new tables, `prinotes_todo_lists` and `prinotes_todos` (additive migration; existing notes are untouched).

### Fixed
- Check circles in the To-Do list were stretched into ovals by Nextcloud's default button sizing.

## [1.1.3] – 2026-10-11

### Fixed
- Sharing a note failed with HTTP 500 on PostgreSQL (`null value in column "share_type"`). `Share::$shareType` defaulted to `'user'`, so Nextcloud's `Entity::setter()` treated `setShareType('user')` as unchanged and left the column out of the INSERT. Defaults are now `null` so the value is always written. (#2)

## [1.0.3] – 2026-08-10

### Fixed
- App store release signing used the wrong RSA padding scheme (PKCS1v15 instead of PSS with SHA-1 digest / SHA-512 MGF1, salt length 0), causing every published release to fail Nextcloud's code signature check with `InvalidSignatureException: Signature could not get verified.`. Releases are now signed correctly.

## [1.0.0] – 2026-05-13

### Added
- Rich block editor: paragraphs, headings (H1–H3), lists, checklists, code blocks, quotes, dividers
- Full-canvas freehand drawing support with undo/redo
- Image attachments with inline resize and rotate
- Notebooks with colour coding and drag-to-reorder
- Tags with colour labels; multi-tag support per note
- Pin notes to top of list
- Per-note colour theming
- Full-text search (title, preview, content)
- Archive and Trash with restore and permanent delete
- Per-note PIN lock (content hidden from search and previews when locked)
- App-wide PIN lock + biometric unlock (Android)
- Hidden notes vault — notes revealed only by typing a secret vault password in search
- Android offline-first client with automatic background sync (every 60 s)
- Grid and list view with persistent preference
- Dark / light / system theme (web + Android)
- Nextcloud 25–33 compatibility
