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
3. In **Signing & Capabilities**, select your Development Team
4. Build and run (⌘R)

## TestFlight / App Store

To archive and upload to TestFlight:

1. In **Signing & Capabilities**, set your Development Team and ensure Automatic signing is enabled
2. Register the bundle identifier (`com.piperly.app`) in [App Store Connect](https://appstoreconnect.apple.com) — or change it to one under your developer account
3. Create the app in App Store Connect (set name, category, age rating, etc.)
4. In Xcode: **Product → Archive**
5. In the Organizer window: **Distribute App → App Store Connect → Upload**
6. In App Store Connect: add testers under **TestFlight** and submit for review

Internal testers (up to 100) can install immediately after upload. External testers require a brief Apple review (~24 hours).

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
