# PriNotes — Rich Note-Taking for Nextcloud

**PriNotes** is a privacy-first, feature-rich note-taking app that runs entirely on your own Nextcloud server. Your notes never touch a third-party cloud.

---

## Features

| Category | Feature |
|---|---|
| **Editor** | Paragraphs, headings, lists, checklists, code blocks, quotes, dividers |
| **Media** | Freehand drawing, image attachments with resize & rotate |
| **Organisation** | Notebooks, tags, pin, archive, trash |
| **Search** | Full-text search across title, preview, and content |
| **Security** | Per-note PIN lock, app-wide PIN + biometric (Android), hidden notes vault |
| **Android** | Offline-first with automatic background sync |
| **Theming** | Dark / light / system theme on both web and Android |

---

## Screenshots

> Screenshots coming soon.

---

## Installation — Nextcloud App (Web)

### Option A — Manual install
1. Download the latest release archive from the [Releases page](https://github.com/UrbanTechIO/nextcloud-prinotes/releases)
2. Extract the `prinotes` folder into your Nextcloud `custom_apps/` directory
3. In Nextcloud go to **Apps → Your apps** and enable **PriNotes**

### Option B — From source
```bash
cd /var/www/html/custom_apps
git clone https://github.com/UrbanTechIO/nextcloud-prinotes.git prinotes
cd prinotes
npm install --legacy-peer-deps
npm install terser --save-dev --legacy-peer-deps
npm run build
```
Then enable the app in Nextcloud.

---

## Installation — Android App

The Android app connects to your Nextcloud instance for sync. It works fully offline and syncs in the background.

### Steps
1. Go to the [Releases page](https://github.com/UrbanTechIO/nextcloud-prinotes/releases) and download `prinotes-android-1.0.0.apk`
2. On your Android device, go to **Settings → Apps → Special app access → Install unknown apps**
3. Allow your browser (or Files app) to install APKs
4. Open the downloaded `.apk` and tap **Install**

### First-time setup
1. Open PriNotes on your phone
2. Enter your **Nextcloud server URL** (e.g. `https://cloud.example.com`)
3. Enter your Nextcloud **username**
4. Generate an **App Password** in Nextcloud under **Settings → Security → App passwords** and paste it in

> **Note:** Use a Nextcloud app password, not your main account password.

---

## Android App — Build from Source

Requirements: Flutter 3.x, Android SDK

```bash
cd android-app
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk --release
# APK will be at: build/app/outputs/flutter-apk/app-release.apk
```

---

## Nextcloud Compatibility

| PriNotes | Nextcloud |
|---|---|
| 1.0.x | 25 – 33 |

---

## Security Model

- **Per-note lock** — notes locked with a PIN show only the title in lists and search; content is never exposed until unlocked
- **App lock** — the entire Android app can be protected with a PIN and/or biometric authentication
- **Hidden notes vault** — a separate secret vault: type `::vault` in the search bar to configure a vault password; hidden notes only appear when the correct vault password is typed into the search bar (session-only, resets on app restart)
- **All data stays on your server** — no telemetry, no external services

---

## Tech Stack

| Layer | Technology |
|---|---|
| Nextcloud app backend | PHP 8, Nextcloud OCA framework |
| Web frontend | Vue 3, Vite, custom block editor |
| Android app | Flutter / Dart, Drift (SQLite), Riverpod |
| Sync | REST API with incremental push/pull |

---

## License

[GNU AGPL v3.0](LICENSE)

---

## Contributing

Issues and pull requests are welcome on the [GitHub repository](https://github.com/UrbanTechIO/nextcloud-prinotes).
