# CloudKit sync implementation

Status: accepted

## Context

ADR 0001 chooses private iCloud sync for the Shared Library and per-profile
Reading State. Piperly currently keeps EPUB files and covers in local Documents
folders and encodes model arrays in `UserDefaults`. The app must stay fully
usable offline and must not require a Piperly account or expose child-adjacent
data outside the family's private iCloud database.

The deployment target is iPadOS 17, so Piperly can use `CKSyncEngine`. Apple
recommends it when an app needs control over an existing local model while the
system schedules private-database fetches and sends. `CKAsset` is intended for
external files attached to records and fits EPUB and cover transfer.

SwiftData with CloudKit is not selected because adopting a new persistent
object graph would make this change much larger, while still leaving book-file
lifecycle work outside the model store. iCloud Documents is not selected
because Piperly also needs structured records, explicit conflict behavior, and
parent-facing sync state. Direct `CKDatabase` operations are not selected
because Piperly would have to own change tokens, scheduling, notifications,
and retry behavior that `CKSyncEngine` already provides.

## Decision

Piperly will use one custom record zone in the user's private CloudKit database,
managed by `CKSyncEngine`. The on-device store remains the source used by the UI
and reader. CloudKit is a replicated transport, not a live network dependency.
Every local change is saved locally first and added to a durable pending-change
queue. Sync can stop, retry, or be unavailable without blocking reading.

Sync is off by default until a parent enables it. The active profile selection
is device-local; profiles and their Reading State sync, but which profile is
currently selected does not.

### Container and zone

- Container: `iCloud.com.piperly.app`.
- Database: private database only.
- Zone: `PiperlyLibrary`.
- The app needs the iCloud/CloudKit and remote-notification capabilities.
- The engine state and pending changes are encoded in the local application
  support directory, separately from user-visible model data.
- Account changes invalidate engine state and immediately quarantine pending
  work so it cannot be sent to a different account. After the parent confirms
  the currently signed-in account, Piperly starts a fetch-only engine and
  reconciles remote data before allowing any send. The parent must explicitly
  choose whether to discard the previous account's pending work or keep the
  local work and upload it after that fresh fetch. Until a choice is made, sync
  remains paused. Fetched changes are staged durably during this window rather
  than applied to local models or files. Keeping local work suppresses fetched
  tombstones for those captured or quarantined records; discarding local work
  applies the staged remote state before sync resumes.

The container identifier must be created for team `7CNK4YPCQX`, attached to the
app identifier, tested in the development environment, and promoted to
production before TestFlight or App Store builds.

### Record schema

Record names are deterministic and never contain a nickname, title, saved word,
or other user content.

| Record type | Record name | Important fields |
| --- | --- | --- |
| `Book` | lowercase EPUB SHA-256 | local UUID, title, author, original extension, cover availability, modified date, EPUB asset, optional cover asset |
| `ReaderProfile` | `profile-<profile UUID>` | nickname, avatar symbol, color, created date, modified date |
| `ReaderPreferences` | `preferences-<profile UUID>` | profile UUID, voice identifier, speech rate, font size, reader theme, voice-setup completion, modified date |
| `ReadingState` | `reading-<profile UUID>-<book hash>` | profile UUID, book hash, progression, locator JSON, modified date |
| `Bookmark` | `bookmark-<bookmark UUID>` | profile UUID, book hash, locator JSON, title, progression, sticker, created date, modified date |
| `SavedWord` | `word-<saved-word UUID>` | profile UUID, book hash, canonical word, display word, book title snapshot, tap count, saved date, last-tapped date, modified date |

Book-linked cloud records use the EPUB hash, not the local Book UUID. The Book
record may carry the local UUID so a downloaded replica can preserve it, but
the hash is the cross-device join key and deduplication key.

Record fields are additive after production deployment. Renaming or deleting a
record type or field requires a new field and a compatibility period.
Record names share one namespace within the custom zone, so every UUID-backed
type has a type prefix even when UUID collisions are unlikely.

### Local sync boundary

`BookStore` will not call CloudKit directly. It will send typed local changes to
a `LibrarySyncing` interface and apply typed remote changes returned by that
interface. Production uses `CloudKitLibrarySync`; tests use an in-memory fake.

The sync layer owns:

- encoding models to and from `CKRecord`;
- durable `CKSyncEngine.State.Serialization` data;
- durable pending record saves and deletions;
- account and engine status;
- asset staging and local availability;
- mapping CloudKit errors to small user-facing states.

The local persistence layer owns model arrays and file URLs. A remote batch is
applied atomically from the UI's point of view, then published on the main actor.
Remote application must not enqueue the same records as new local changes.

### Send and fetch lifecycle

1. A local save or deletion is written to a durable, serialized outbox before
   the local mutation returns to its caller.
2. Its deterministic record ID is added to the pending-save queue, or to the
   pending-delete queue for deletion. The outbox entry is removed only after
   the sync layer has durably accepted it.
   If the outbox cannot be read or written, sync enters a blocked state and
   the local mutation does not commit; unreadable queue data is never replaced
   with an empty queue.
3. The sync engine is told that pending work exists.
4. When the engine requests changes, the sync layer supplies current records
   and staged assets for those IDs.
5. Successful sends remove pending entries. Retryable failures remain queued
   with backoff. Permanent validation failures become a visible blocked state.
6. Fetched changes and deletions are decoded, validated, and applied locally.
   Child records whose parents have not arrived are retained durably and
   retried after later records and fetch batches.
7. Engine state is persisted after every state update.

Partial failures are handled per record. `networkUnavailable`, `networkFailure`,
`serviceUnavailable`, `requestRateLimited`, and `zoneBusy` remain retryable.
Account absence, restricted accounts, quota exhaustion, asset-file loss, and
schema/permission errors are surfaced distinctly.

### Conflict rules

- **Book metadata:** one Book per content hash. Non-empty title and author from
  the record with the newest modified date win. Assets are immutable for a
  given hash; differing bytes are treated as corruption, not a normal conflict.
- **Reader Profile:** newest modified date wins for nickname, avatar, and color.
  Deletion wins over an older edit.
- **Reader Preferences:** field set from the newest modified date wins.
- **Reading State:** highest `modifiedAt` wins, except that progression never
  regresses at the same locator. Because `modifiedAt` is an untrusted device wall
  clock, a same-locator decrease is treated as clock skew and the higher
  progression is kept; a genuine move to a different locator may lower it. A
  locator and progression are written together so they cannot come from different
  versions.
- **Bookmark:** records are independent. Same UUID uses newest modified date.
- **Saved Word:** same UUID uses newest display metadata, maximum tap count, the
  earliest saved date, and the latest last-tapped date.

All records retain the CloudKit system fields needed for optimistic saves.
Server-record-changed errors are merged by these rules and retried once through
the normal pending queue.

### Deletion and tombstones

Local deletion immediately hides the item, removes or quarantines local files,
and enqueues the record deletion. CloudKit deletion is the durable tombstone.
Remote deletions cascade locally:

- deleting a Book deletes its local EPUB, cover, Reading States, Bookmarks, and
  Saved Words for that book;
- deleting a Reader Profile deletes its Preferences and profile-scoped Reading
  States, Bookmarks, and Saved Words;
- the final Reader Profile cannot be deleted locally.

If a delete cannot be sent, its tombstone remains queued so a later fetch does
not resurrect locally deleted data. A newer explicit re-import of the same EPUB
can recreate the Book record after the deletion has reached the server.

### EPUB and cover assets

EPUBs and covers are `CKAsset` fields on the Book record. Uploads use immutable
staging copies so the file cannot change while CloudKit reads it. Downloaded
assets arrive in a temporary staging location and are verified before an atomic
move into Piperly's managed library.

Asset state is device-local:

- `local`: verified file is ready;
- `uploading` or `downloading`: progress may be shown when available;
- `remoteOnly`: metadata exists but no verified local file exists;
- `retryableFailure`: parent can retry and the engine can back off;
- `unavailable`: account, quota, permission, or corrupt-file problem.

The SHA-256 of every downloaded EPUB must equal the Book record name before it
becomes readable. Covers are derived data and may be downloaded or regenerated.
Eviction removes only the local asset and keeps metadata. Deleting removes both
the record and local assets.

### Privacy and parent controls

Only the private database is used. No CloudKit user discovery or sharing API is
used. The app stores no birthdate, full name, photo, email address, or Apple ID.
Parent-facing Settings explains that book titles, EPUB files, saved words, and
Reading State use the family's private iCloud storage and count against their
iCloud quota.

The parent gate protects enable, disable, retry/reset, and destructive sync
actions. Normal reading and profile switching remain child-accessible. Turning
sync off stops network work but does not delete local data. Cloud deletion is a
separate confirmed action.

### Test strategy

CloudKit-dependent code is behind interfaces for the container/database,
engine events, state store, clock, and asset staging. Unit tests cover record
round trips, deterministic IDs, pending queue persistence, retry classification,
conflict merges, deletion cascades, hash verification, account changes, and the
rule that applying remote changes does not re-enqueue them.

Simulator tests use fakes and do not claim end-to-end CloudKit coverage. Before
release, test two physical iPads on the same iCloud account for import, offline
read/edit, convergence, duplicate import, profile isolation, conflict, delete,
evict/redownload, account sign-out/in, quota/account errors, and app relaunch
during upload/download. Observe CloudKit and app logs; push notifications are an
optimization and must not be the only way changes are fetched.

## Delivery stack

Each PR is based on the branch immediately before it.

1. `docs(icloud): define sync architecture` — this ADR and setup contract.
2. `feat(profiles): scope reader preferences` — profile-level voice, theme,
   font, rate, setup state, validation, and tests.
3. `feat(library): add stable book identity` — SHA-256 identity, deterministic
   storage, duplicate prevention, and tests.
4. `feat(icloud): add private sync engine` — capabilities, zone, engine state,
   pending queues, record codecs, account/error states, fakes, and tests.
5. `feat(icloud): sync book assets` — EPUB/cover asset lifecycle, verification,
   availability, progress, retry, eviction, deletion, conflicts, and tests.
6. `feat(settings): add iCloud controls` — parent controls and status, the
   account-transition choice, recovery UI, privacy documentation, schema
   promotion, and two-device checklist.

## Consequences

The app keeps working when iCloud is slow or unavailable, and CloudKit-specific
code stays outside reading UI and core models. The cost is an explicit local
change queue, merge rules, and a physical-device test matrix. Development builds
can compile and test with fakes before the Apple container is configured, but
real sync cannot be declared complete until the container, production schema,
entitlements, and two-device tests are verified.

## References

- [Deciding whether CloudKit is right for your app](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app)
- [CloudKit](https://developer.apple.com/documentation/cloudkit/)
- [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)
- [Designing and Creating a CloudKit Database](https://developer.apple.com/documentation/cloudkit/designing-and-creating-a-cloudkit-database)
