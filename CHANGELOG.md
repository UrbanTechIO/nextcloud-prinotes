# Changelog

All notable changes to PriNotes are documented here.

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
