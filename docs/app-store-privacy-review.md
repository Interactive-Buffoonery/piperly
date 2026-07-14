# App Store Privacy And Child-Safety Review

This note records Piperly's current privacy, App Store Connect, and
child-safety posture for public review.

## Audit Conclusion

Piperly can continue to declare no tracking and no developer-collected data in
`Piperly/Resources/PrivacyInfo.xcprivacy`.

The app stores reading state locally and does not include external catalog
browsing, account creation, analytics, advertising, tracking, in-app purchases,
social features, or a developer-hosted backend. The current manifest's
UserDefaults required-reason declaration remains accurate because the app uses
UserDefaults and `@AppStorage` for app-created settings and local reading
metadata.

When a parent enables iCloud sync, EPUB files, book titles, reader profiles,
reading state, bookmarks, saved words, and reader preferences are sent only to
the user's private CloudKit database. They use the family's Apple iCloud
account and storage quota. Piperly does not use CloudKit sharing, user discovery,
analytics, or a developer-hosted account service.

## Actual Data Flows

### Local-only app data

- Reader progress, last locator JSON, book metadata, bookmarks, saved words,
  tap counts, and sample-import state are app-created local state.
- Voice setup, selected voice identifier, speech rate, reader font size, and
  reader theme are app-created preferences.
- Text-to-speech uses `AVSpeechSynthesizer` on device.
- The WebKit reader bridge receives tapped words from locally opened EPUB
  content and saves them locally.

### UserDefaults data

- `BookStore` stores `piperly_books`, `piperly_bookmarks`,
  `piperly_saved_words`, and `piperly_samples_imported`.
- SwiftUI `@AppStorage` stores reader preferences and voice setup state.
- This is the reason for `NSPrivacyAccessedAPICategoryUserDefaults` with reason
  `CA92.1`: Piperly accesses defaults written by the app itself.

### Files in the app documents directory

- Imported EPUB files are copied into `Documents/Books`.
- Extracted cover images are written into `Documents/Covers`.

### Private iCloud data

- iCloud sync is off until a parent enables it through the parent gate.
- Synced data stays in the user's private CloudKit database. Piperly's developer
  does not receive it through an analytics, account, or backend service.
- Turning sync off stops network activity and preserves local data.
- Account changes require a fresh fetch and an explicit parent choice before
  pending work can be uploaded to the newly signed-in account.
- EPUB files and their related data count against the user's iCloud quota.

### Readium and third-party dependencies

- Piperly directly depends on Readium Swift Toolkit products:
  `ReadiumShared`, `ReadiumStreamer`, and `ReadiumNavigator`.
- The current repo uses Readium to parse local EPUBs and render EPUB content.
- Piperly does not include an analytics SDK, advertising SDK, account system,
  external catalog integration, or developer-accessible data collection path.

## Privacy Manifest

Current manifest answer:

- `NSPrivacyTracking`: `false`
- `NSPrivacyTrackingDomains`: empty
- `NSPrivacyCollectedDataTypes`: empty
- `NSPrivacyAccessedAPITypes`: UserDefaults with reason `CA92.1`

No functional manifest expansion is needed for the current app behavior.

Do not add collected data types unless Piperly starts sending data to the app
developer, an integrated third-party service, analytics, crash reporting,
advertising, an account backend, or another service whose data the developer or
a partner can access beyond real-time request handling.

## Recommended App Store Connect Privacy Answers

Use these answers for the current app behavior:

- Does this app collect data from this app? **No**
- Is data used to track users? **No**
- Tracking domains: **None**
- Data linked to user: **None**
- Data not linked to user: **None**
- Privacy policy URL: required for App Store submission; use the external policy
  language below as the starting point.

## Kids Category And Child-Facing Posture

Piperly is child-facing and currently uses the Education category in
`project.yml`. If Piperly opts into the App Store Kids Category, keep this
posture:

- No ads, tracking, behavioral analytics, social sharing, public profiles, chat,
  purchases, account creation, external catalog browsing, or web browsing are
  present.
- Imported books are parent-supplied content. App Store metadata should not
  claim Apple has reviewed or curated imported EPUB content.
- If future work adds external links, purchases, web browsing, sharing,
  sign-in, hosted catalog content, or external catalog browsing, revisit the
  child-safety review before TestFlight or App Store submission.

## External Privacy Policy Draft

Use this as a publishable starting point for the public privacy policy:

> Piperly does not collect, sell, share, or track personal information.
>
> Piperly stores reading information on your device, including imported books,
> cover images, reading progress, bookmarks, saved words, tap counts, reader
> preferences, and voice preferences. This information is used only to provide
> the reading experience inside the app.
>
> If a parent enables iCloud sync, Piperly stores EPUB files, book titles,
> reader profiles, reading state, bookmarks, saved words, and reader preferences
> in the family's private iCloud account so they can be used on the family's
> devices. This information counts against the account's iCloud storage quota.
>
> Piperly does not include advertising, third-party analytics, social networking,
> account creation, external catalog browsing, or in-app purchases.
>
> Turning iCloud sync off keeps reading data already stored on the device and
> does not delete cloud data. To remove local reading data, delete books from
> the app or delete Piperly from the device.

## Repo Evidence Checked

- `Piperly/App/ContentView.swift`
- `Piperly/Views/Settings/SettingsView.swift`
- `Piperly/Services/BookStore.swift`
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
