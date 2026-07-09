// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import Foundation
import Testing
@testable import Piperly

@Suite("CloudKit sync correctness fixes")
struct SyncCorrectnessFixTests {
    @Test func skewedFutureTimestampCannotRegressReadingProgress() {
        let profileID = UUID()
        let identity = String(repeating: "a", count: 64)
        // Local: newer real progress at an earlier honest clock time.
        let local = SyncedReadingState(
            profileID: profileID,
            bookIdentity: identity,
            progression: 0.8,
            locatorJSON: "{\"pos\":80}",
            modifiedAt: Date(timeIntervalSince1970: 1000)
        )
        // Remote from a device whose clock runs a day fast, but less progress.
        let skewedRemote = SyncedReadingState(
            profileID: profileID,
            bookIdentity: identity,
            progression: 0.2,
            locatorJSON: "{\"pos\":80}",
            modifiedAt: Date(timeIntervalSince1970: 1000 + 86_400)
        )

        let merged = LibraryConflictResolver.merge(local: local, remote: skewedRemote)
        #expect(merged.progression == 0.8)

        // A genuine move to a different locator may still lower progression.
        var movedRemote = skewedRemote
        movedRemote.locatorJSON = "{\"pos\":15}"
        let movedMerge = LibraryConflictResolver.merge(local: local, remote: movedRemote)
        #expect(movedMerge.progression == 0.2)
    }

    @Test @MainActor func remoteReadingStateDoesNotRegressLocalProgress() throws {
        let fixture = try Self.storeFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let identity = String(repeating: "d", count: 64)
        let bookID = UUID()
        store.books = [Book(
            id: bookID,
            contentIdentity: identity,
            title: "Book",
            author: "Author",
            fileName: "\(identity).epub",
            modifiedAt: Date(timeIntervalSince1970: 100)
        )]
        store.readingStates = [ReadingState(
            profileID: store.activeProfile.id,
            bookID: bookID,
            lastReadProgression: 0.9,
            lastReadLocatorJSON: "{\"pos\":90}",
            updatedAt: Date(timeIntervalSince1970: 1000)
        )]

        _ = store.applyRemoteChanges([.save(.readingState(SyncedReadingState(
            profileID: store.activeProfile.id,
            bookIdentity: identity,
            progression: 0.1,
            locatorJSON: "{\"pos\":90}",
            modifiedAt: Date(timeIntervalSince1970: 1000 + 86_400)
        )))])

        #expect(store.readingStates.first?.lastReadProgression == 0.9)
    }

    @Test func deferredRecordsAreCappedAndTombstonesExpire() {
        var snapshot = SyncStateSnapshot.empty
        let cap = SyncSnapshotMaintenance.maxBucketEntries
        // Over-fill the deferred bucket; newest-by-modifiedAt survive.
        for index in 0..<(cap + 50) {
            let record = LibraryRecord.book(SyncedBook(
                id: UUID(),
                contentIdentity: String(format: "%064x", index),
                title: "Book \(index)",
                author: "Author",
                originalExtension: "epub",
                hasCover: false,
                modifiedAt: Date(timeIntervalSince1970: Double(index))
            ))
            snapshot.deferredRemoteRecords[record.reference.recordName] = record
        }
        // Old + fresh tombstones.
        let now = Date(timeIntervalSince1970: 10_000_000)
        SyncSnapshotMaintenance.recordTombstone(
            "stale",
            at: now.addingTimeInterval(-SyncSnapshotMaintenance.tombstoneLifetime - 1),
            snapshot: &snapshot
        )
        SyncSnapshotMaintenance.recordTombstone("fresh", at: now, snapshot: &snapshot)

        SyncSnapshotMaintenance.prune(now: now, snapshot: &snapshot)

        #expect(snapshot.deferredRemoteRecords.count == cap)
        #expect(snapshot.tombstones["stale"] == nil)
        #expect(snapshot.tombstones["fresh"] != nil)
    }

    @Test func tombstoneBlocksOlderSaveButNotNewer() {
        var snapshot = SyncStateSnapshot.empty
        let now = Date(timeIntervalSince1970: 1_000_000)
        SyncSnapshotMaintenance.recordTombstone("book-x", at: now, snapshot: &snapshot)

        // An incoming save that predates the delete must not resurrect the record.
        #expect(SyncSnapshotMaintenance.isBlockedByTombstone(
            "book-x",
            incomingModifiedAt: now.addingTimeInterval(-10),
            now: now,
            snapshot: snapshot
        ))
        // A genuinely newer save (a real re-import after the delete) is allowed.
        #expect(!SyncSnapshotMaintenance.isBlockedByTombstone(
            "book-x",
            incomingModifiedAt: now.addingTimeInterval(10),
            now: now,
            snapshot: snapshot
        ))
        // After the retention window the tombstone no longer blocks anything.
        #expect(!SyncSnapshotMaintenance.isBlockedByTombstone(
            "book-x",
            incomingModifiedAt: now.addingTimeInterval(-10),
            now: now.addingTimeInterval(SyncSnapshotMaintenance.tombstoneLifetime + 1),
            snapshot: snapshot
        ))
    }

    @MainActor
    private static func storeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-syncfix-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "PiperlyTests.SyncFix.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return Fixture(
            store: BookStore(
                documentsURL: root.appendingPathComponent("Books", isDirectory: true),
                coversURL: root.appendingPathComponent("Covers", isDirectory: true),
                userDefaults: defaults,
                librarySync: DisabledLibrarySync()
            ),
            root: root,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    @MainActor
    private struct Fixture {
        let store: BookStore
        let root: URL
        let defaults: UserDefaults
        let suiteName: String

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
