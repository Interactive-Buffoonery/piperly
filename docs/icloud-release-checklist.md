# iCloud Release Checklist

Complete every item before describing iCloud sync as release-ready. Simulator
and fake-based tests do not replace the physical-device checks below.

## Apple Developer And CloudKit Setup

- [ ] Create `iCloud.com.piperly.app` for team `7CNK4YPCQX`.
- [ ] Attach the container to app identifier `com.piperly.app`.
- [ ] Confirm the iCloud/CloudKit and remote-notification capabilities are on
  the App ID, development profile, distribution profile, and Xcode target.
- [ ] Confirm the app uses only the private CloudKit database and the
  `PiperlyLibrary` custom zone.
- [ ] Launch a development-signed build and create every record type and field
  listed in ADR 0002 in the development environment.
- [ ] Inspect representative records and confirm record names contain hashes or
  prefixed UUIDs, never titles, nicknames, or saved words.
- [ ] Add indexes only where the shipped queries require them.
- [ ] Promote the complete schema to production before TestFlight upload.
- [ ] Confirm the production schema in CloudKit Console. Production fields
  cannot be renamed or removed safely after release.

## Automated Checks

- [ ] Run `xcodegen generate`.
- [ ] Run the full `Piperly` scheme on an iPad simulator.
- [ ] Confirm unit tests cover the parent gate, enable/disable behavior, account
  policy choice, blocked/retry status copy, asset retry, and accessibility.
- [ ] Lint `Piperly/Info.plist` and `Piperly/Resources/PrivacyInfo.xcprivacy`.
- [ ] Confirm no new required-reason API was added. CloudKit itself does not
  require a new entry in the privacy manifest.

## Two Physical iPads, Same iCloud Account

Use two physical iPads signed into the same test iCloud account. Start with
clean installs and record the app build, iPadOS versions, account, and time.

- [ ] Enable sync through the parent gate on both devices.
- [ ] Import an EPUB on iPad A; confirm its title, cover, and readable EPUB arrive
  on iPad B without relaunching either app.
- [ ] Create separate reader profiles and confirm profiles and preferences sync
  while each iPad's active-profile selection remains local.
- [ ] Change progress, add bookmarks, and save words on each iPad. Confirm both
  devices converge without mixing profile data.
- [ ] Import the same EPUB on both devices and confirm one book remains.
- [ ] Put iPad B offline. Read, change preferences, bookmark, and save words on
  both devices. Reconnect and confirm all conflict rules from ADR 0002.
- [ ] Make a newer reading-position change on one device and confirm locator and
  progression arrive together.
- [ ] Delete a book and a non-final profile; confirm cascaded data and files are
  removed on the other device and do not reappear.
- [ ] Evict a local EPUB, confirm metadata remains, then redownload and verify it
  opens. Exercise a failed download and the per-book retry button.
- [ ] Turn sync off. Confirm network work stops, local reading still works, and
  neither local nor cloud data is deleted. Re-enable and confirm convergence.
- [ ] Relaunch during EPUB upload and download. Confirm durable retries finish
  and staging files do not leak or corrupt the library.

## Account, Quota, And Failure Recovery

- [ ] Enable with no iCloud account and with a restricted account. Confirm clear,
  recoverable copy and no upload.
- [ ] Switch accounts with no pending work. Confirm the new account is fetched
  before sync resumes.
- [ ] Switch accounts with pending saves and deletes. Test both choices: keep
  local work and upload after the fresh fetch, and discard previous-account
  pending work. Confirm nothing reaches the wrong account.
- [ ] Switch accounts again during confirmation. Confirm the transition stops,
  pending work stays quarantined, and the parent is asked again.
- [ ] Fill the test account's iCloud quota. Confirm the blocked status names the
  quota problem, reading remains available, and retry works after space is freed.
- [ ] Exercise network loss, rate limiting, service unavailability, permission
  failure, invalid schema, missing upload file, and corrupt download where
  practical. Confirm local data remains safe and the UI offers the right retry.
- [ ] Confirm no settings action deletes the CloudKit library. Any future cloud
  deletion action must have its own parent gate and separate confirmation.

## Logs And Sign-Off

- [ ] Capture app logs for engine start/stop, fetch, send, retry, account change,
  asset verification, and blocked states. Logs must not include titles,
  nicknames, saved words, locator JSON, or EPUB contents.
- [ ] Compare app logs with CloudKit Console activity and confirm push
  notifications are an optimization, not the only fetch path.
- [ ] Save the two-iPad test date, testers, device/iPadOS versions, build number,
  production-schema confirmation, failures found, and retest results in the
  release record.
