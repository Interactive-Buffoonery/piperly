# App Store Privacy And Child-Safety Review

This note records Piperly's current privacy, App Store Connect, and
child-safety posture for public review.

## Audit Conclusion

Piperly can continue to declare no tracking and no collected data in
`Piperly/Resources/PrivacyInfo.xcprivacy`.

The app stores reading state locally, stores the parent PIN and optional OPDS
server credentials in Keychain, and makes network requests only when a parent
configures an OPDS server behind Parent Controls and unlocks Browse. The current
manifest's UserDefaults required-reason declaration remains accurate because
the app uses UserDefaults and `@AppStorage` for app-created settings and local
reading metadata.

Apple defines collection for App Store privacy answers as transmitting data off
device in a way that allows the developer or third-party partners to access it
beyond servicing the request in real time. Piperly does not currently send
reading data, credentials, analytics, diagnostics, or identifiers to the app
developer or an integrated analytics, advertising, or backend service.

## Actual Data Flows

### Local-only app data

- Reader progress, last locator JSON, book metadata, bookmarks, saved words,
  tap counts, and sample-import state are app-created local state.
- Voice setup, selected voice identifier, speech rate, reader font size, and
  reader theme are app-created preferences.
- Text-to-speech uses `AVSpeechSynthesizer` on device.
- The WebKit reader bridge receives tapped words from locally opened EPUB
  content and saves them locally.

### Keychain data

- The parent PIN is stored as a SHA-256 hash in Keychain.
- Parent-configured OPDS server URL, username, and password are stored in
  Keychain.
- Keychain items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so they
  stay on the device and are not migrated through backups.

### UserDefaults data

- `BookStore` stores `piperly_books`, `piperly_bookmarks`,
  `piperly_saved_words`, and `piperly_samples_imported`.
- SwiftUI `@AppStorage` stores reader preferences and voice setup state.
- This is the reason for `NSPrivacyAccessedAPICategoryUserDefaults` with reason
  `CA92.1`: Piperly accesses defaults written by the app itself.

### Files in the app documents directory

- Imported EPUB files are copied into `Documents/Books`.
- Extracted cover images are written into `Documents/Covers`.
- OPDS downloads are written to a temporary file, imported into
  `Documents/Books`, then the temporary file is removed.

### OPDS network behavior

- Browse is parent-gated in `Piperly/App/ContentView.swift`.
- Server URL, username, and password entry are hidden behind Parent Controls in
  `Piperly/Views/Settings/SettingsView.swift`.
- Once configured and unlocked, Piperly sends OPDS feed, navigation, search,
  cover image, connection-test, and EPUB download requests to the configured
  server URL.
- If a username is present, requests include an HTTP Basic Authorization header
  built from the stored username and password.
- Piperly does not proxy those requests through the app developer and does
  not include an analytics SDK, advertising SDK, account system, or developer
  backend in the current repo.

### Readium and third-party dependencies

- Piperly directly depends on Readium Swift Toolkit products:
  `ReadiumShared`, `ReadiumStreamer`, `ReadiumNavigator`, and `ReadiumOPDS`.
- The resolved package graph includes `CryptoSwift`, `DifferenceKit`, `Fuzi`,
  `GCDWebServer`, `SQLite.swift`, `SwiftSoup`, `Zip`, and `ZIPFoundation`.
- The current repo uses Readium to parse local EPUBs, render EPUB content, and
  parse OPDS feeds. The app-level audit found no analytics, ads, account sync,
  or developer-accessible data collection path in these integrations.
- Resolved transitive package privacy manifests present in local Xcode
  checkouts declare no tracking and no collected data. `ZIPFoundation` declares
  file timestamp required-reason API use in its own bundled privacy manifest.

## Privacy Manifest

Current manifest answer:

- `NSPrivacyTracking`: `false`
- `NSPrivacyTrackingDomains`: empty
- `NSPrivacyCollectedDataTypes`: empty
- `NSPrivacyAccessedAPITypes`: UserDefaults with reason `CA92.1`

No functional manifest expansion is needed for the current app behavior.

Do not add collected data types unless Piperly starts sending data to
the app developer, an integrated third-party service, analytics, crash
reporting, advertising, an account backend, or another service whose data the
developer or a partner can access beyond real-time request handling.

## Recommended App Store Connect Privacy Answers

Use these answers for the current app behavior:

- Does this app collect data from this app? **No**
- Is data used to track users? **No**
- Tracking domains: **None**
- Data linked to user: **None**
- Data not linked to user: **None**
- Privacy policy URL: required for App Store submission; use the external policy
  language below as the starting point.

Notes for the App Store privacy form:

- Do not mark OPDS server URL, OPDS username/password, reading progress,
  bookmarks, saved words, or EPUB files as collected while they remain local or
  are transmitted only to the parent-configured OPDS server outside
  the app developer's control.
- If Piperly later adds crash reporting, analytics, app telemetry, cloud sync,
  account login, hosted catalogs, support forms, or diagnostics upload, update
  both App Store Connect and `PrivacyInfo.xcprivacy`.

## Kids Category And Child-Facing Posture

Piperly is child-facing and currently uses the Education category in
`project.yml`. If Piperly opts into the App Store Kids Category, keep this
posture:

- External catalog access stays behind the parent PIN.
- Server configuration stays behind Parent Controls.
- No ads, tracking, behavioral analytics, social sharing, public profiles, chat,
  purchases, or account creation are present.
- Imported books and parent-configured OPDS catalogs are parent-supplied
  content. App Store metadata should not claim Apple has reviewed or curated
  external OPDS content.
- Browse should remain unavailable until a parent sets a PIN and unlocks it.
- If future work adds external links, purchases, web browsing, sharing,
  sign-in, or hosted catalog content, revisit the child-safety review before
  TestFlight or App Store submission.

## External Privacy Policy Draft

Use this as a publishable starting point for the public privacy policy:

> Piperly does not collect, sell, share, or track personal information.
>
> Piperly stores reading information on your device, including imported books,
> cover images, reading progress, bookmarks, saved words, tap counts, reader
> preferences, and voice preferences. This information is used only to provide
> the reading experience inside the app.
>
> Piperly stores the parent PIN and any optional book server settings in the
> device Keychain. Book server settings may include a server URL, username, and
> password entered by a parent.
>
> If a parent configures an OPDS-compatible book server, Piperly can connect
> directly to that server to browse catalogs, load cover images, search, test the
> connection, and download EPUB files. If credentials are configured, Piperly
> sends them to that server using HTTP Basic authentication. The Piperly
> developer does not operate this server, proxy these requests, or receive the
> server credentials.
>
> Piperly does not include advertising, third-party analytics, social networking,
> account creation, or in-app purchases.
>
> To remove local reading data, delete books from the app or delete Piperly from
> the device. To remove saved book server credentials, clear or replace them in
> Parent Controls or remove the app from the device.

## Repo Evidence Checked

- `Piperly/App/ContentView.swift`
- `Piperly/Views/Settings/SettingsView.swift`
- `Piperly/Services/BookStore.swift`
- `Piperly/Services/KeychainService.swift`
- `Piperly/Services/PINManager.swift`
- `Piperly/Models/OPDSServerConfig.swift`
- `Piperly/Services/OPDSService.swift`
- `Piperly/Services/AuthenticatedImageLoader.swift`
- `Piperly/Views/Reader/ReaderView.swift`
- `Piperly/App/PiperlyApp.swift`
- `Piperly/Resources/PrivacyInfo.xcprivacy`
- `project.yml`
- `Piperly.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

## Apple References

- [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy in App Store Connect](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Design safe and age-appropriate experiences](https://developer.apple.com/app-store/kids-apps/)
