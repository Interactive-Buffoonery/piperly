# Piperly

An iPad ebook reader for kids. Tap a word, hear it spoken.

Piperly loads EPUB books, wraps every word in a tappable element, and uses on-device text-to-speech to read words aloud. Kids build vocabulary by tapping words they don't know — each tap saves the word to a personal word list they can review later.

## Features

- **EPUB reader** powered by [Readium Swift Toolkit](https://github.com/readium/swift-toolkit)
- **Tap-to-speak** — tap any word to hear it read aloud via AVSpeechSynthesizer
- **Word list** — automatically tracks tapped words with tap counts and book source
- **Sticker bookmarks** — kids mark pages with fun stickers instead of boring bookmark icons
- **7 reader themes** — Piperly, Sunset, Ocean, Forest, Midnight, Cream, High Contrast
- **OPDS catalog browsing** — connect to book servers to discover and download EPUBs
- **PIN-protected settings** — parents control voice, theme, and server settings

## Requirements

- **Xcode 16.0+** (full install, not just Command Line Tools)
- **iOS 17.0+ / iPadOS 17.0+** (iPad only)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — generates the Xcode project from `project.yml`
- [SwiftLint](https://github.com/realm/SwiftLint) — optional, lints on build if installed

## Getting Started

```bash
# Clone
git clone git@github.com:Interactive-Buffoonery/piperly.git
cd piperly

# Install tools
brew install xcodegen
brew install swiftlint  # optional

# Generate Xcode project
xcodegen

# Open in Xcode
open Piperly.xcodeproj
```

Xcode will automatically resolve the Readium Swift Package Manager dependencies on first open. This can take a few minutes.

## Building

1. Open `Piperly.xcodeproj` in Xcode
2. Select an iPad simulator or connected iPad device
3. For device builds or archives, select your own Development Team in
   **Signing & Capabilities**
4. Build and run (⌘R)

For command-line verification, regenerate the project and use the shared `Piperly`
scheme:

```bash
xcodegen generate
xcodebuild -project Piperly.xcodeproj -scheme Piperly -showdestinations
xcodebuild -project Piperly.xcodeproj \
  -scheme Piperly \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The CLI build requires the iOS platform components for the active Xcode version
to be installed in **Xcode > Settings > Components**.

## TestFlight / App Store

See [docs/testflight-release-checklist.md](docs/testflight-release-checklist.md)
for the repo-side metadata audit and archive checklist.

To archive and upload to TestFlight, configure signing with your own Apple
developer account, register an appropriate bundle identifier in
[App Store Connect](https://appstoreconnect.apple.com), create the app record,
then archive and upload from Xcode Organizer. Keep signing identities,
provisioning profiles, and local account settings out of the repository.

### Privacy Review

See [docs/app-store-privacy-review.md](docs/app-store-privacy-review.md) for the
current App Store Connect privacy answers, Kids Category posture, and external
privacy policy draft. The current repo posture is no tracking and no collected
data; local reading state remains on device, and optional OPDS access is
parent-gated.

### Parent Gate Regression Checklist

- Fresh install with no PIN: **Browse** prompts for parent PIN setup before any
  catalog content loads.
- Fresh install with no PIN: **Settings** shows reading settings and parent PIN
  setup, but hides server URL, username, and password fields.
- After PIN setup: **Browse** requires the PIN before catalog browsing.
- After PIN setup: **Settings > Parent Controls** requires the PIN before server
  configuration, while library reading remains available without a PIN.

## Project Structure

```
Piperly/
├── App/                  # App entry point
├── Models/               # Book, Bookmark, SavedWord, CatalogItem, Voice, etc.
├── Services/             # BookStore, TTSEngine, OPDSService, PINManager, Keychain
├── Theme/                # Colors, Typography, ReaderTheme
├── Views/
│   ├── Library/          # Book grid, import, book cards
│   ├── Reader/           # EPUB reader, toolbar, word tap, TOC, bookmarks
│   ├── Settings/         # PIN gate, voice setup, reading settings
│   ├── Catalog/          # OPDS server browsing and download
│   └── Words/            # Saved word list and word chips
├── Resources/
│   ├── Assets.xcassets/  # App icon and colors
│   ├── word-tap.js       # JS injected into EPUB for word tap detection
│   ├── reader-theme.css  # Base reader styles
│   └── PrivacyInfo.xcprivacy
└── docs/                 # Design mockups and color palette
```

## License

Piperly is licensed under the [GNU General Public License v3.0](LICENSE).
