import CloudKit
import Foundation
import Testing
@testable import Piperly

@Suite("Book asset staging")
struct BookAssetStagingTests {
    @Test func uploadUsesImmutableCopyUntilCleanedUp() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.epub")
        try Data("first".utf8).write(to: source)
        let staging = BookAssetStaging(rootURL: root.appendingPathComponent("staging"))

        let files = try staging.stageUpload(BookAssetURLs(epub: source, cover: nil), recordName: "hash")
        let stagedEPUB = try #require(files.epub)
        try Data("changed".utf8).write(to: source)

        #expect(try Data(contentsOf: stagedEPUB) == Data("first".utf8))
        staging.cleanup(files)
        #expect(!FileManager.default.fileExists(atPath: stagedEPUB.path))
    }

    @Test func bookRecordCarriesEPUBAndOptionalCoverAssets() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let epub = root.appendingPathComponent("book.epub")
        let cover = root.appendingPathComponent("cover.jpg")
        try Data("epub".utf8).write(to: epub)
        try Data("cover".utf8).write(to: cover)
        let identity = try BookAssetStaging.sha256(of: epub)
        let value = LibraryRecord.book(SyncedBook(
            id: UUID(),
            contentIdentity: identity,
            title: "Book",
            author: "Author",
            originalExtension: "epub",
            hasCover: true,
            modifiedAt: .now
        ))

        let record = try LibraryRecordCodec.encode(
            value,
            bookAssets: BookAssetURLs(epub: epub, cover: cover)
        )

        #expect((record["epubAsset"] as? CKAsset)?.fileURL == epub)
        #expect((record["coverAsset"] as? CKAsset)?.fileURL == cover)
    }

    @Test func verifiedDownloadPublishesAtomically() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let temporary = root.appendingPathComponent("cloud.epub")
        try Data("verified book".utf8).write(to: temporary)
        let identity = try BookAssetStaging.sha256(of: temporary)
        let staging = BookAssetStaging(rootURL: root.appendingPathComponent("staging"))
        let files = try staging.stageDownload(BookAssetURLs(epub: temporary, cover: nil), recordName: identity)
        let destination = root.appendingPathComponent("Books/\(identity).epub")

        _ = try staging.publishDownload(files, identity: identity, epubDestination: destination, coverDestination: nil)

        #expect(try Data(contentsOf: destination) == Data("verified book".utf8))
    }

    @Test func hashMismatchNeverPublishes() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let temporary = root.appendingPathComponent("cloud.epub")
        try Data("corrupt".utf8).write(to: temporary)
        let staging = BookAssetStaging(rootURL: root.appendingPathComponent("staging"))
        let files = try staging.stageDownload(BookAssetURLs(epub: temporary, cover: nil), recordName: "wrong")
        let destination = root.appendingPathComponent("Books/wrong.epub")

        #expect(throws: BookAssetError.hashMismatch) {
            try staging.publishDownload(files, identity: "wrong", epubDestination: destination, coverDestination: nil)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func differingBytesForOneClaimedIdentityAreCorruption() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("local.epub")
        let remote = root.appendingPathComponent("remote.epub")
        try Data("local".utf8).write(to: local)
        try Data("remote".utf8).write(to: remote)

        #expect(try !BookAssetStaging.filesMatch(local, remote))
    }

    @Test func overlappingUploadsKeepIndependentImmutableStages() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.epub")
        try Data("same bytes".utf8).write(to: source)
        let staging = BookAssetStaging(rootURL: root.appendingPathComponent("staging"))

        let first = try staging.stageUpload(BookAssetURLs(epub: source, cover: nil), recordName: "book")
        let second = try staging.stageUpload(BookAssetURLs(epub: source, cover: nil), recordName: "book")
        let firstURL = try #require(first.epub)
        let secondURL = try #require(second.epub)
        #expect(firstURL != secondURL)

        staging.cleanup(first)
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
    }

    @Test func uploadValidationRejectsIdentityMismatch() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.epub")
        try Data("book".utf8).write(to: source)
        let staging = BookAssetStaging(rootURL: root.appendingPathComponent("staging"))
        let staged = try staging.stageUpload(BookAssetURLs(epub: source, cover: nil), recordName: "wrong")

        #expect(throws: BookAssetError.hashMismatch) {
            try staging.validateUpload(staged, identity: String(repeating: "0", count: 64))
        }
    }

    @Test func missingAndUnreadableUploadsHaveRecoverableClassifications() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = BookAssetStaging(rootURL: root.appendingPathComponent("staging"))
        let missing = root.appendingPathComponent("missing.epub")

        #expect(throws: BookAssetError.missingEPUB) {
            _ = try staging.stageUpload(BookAssetURLs(epub: missing, cover: nil), recordName: "book")
        }
        #expect(BookAssetFailureClassifier.classify(BookAssetError.missingEPUB) == .missingLocalData)
        // A leftover transaction dir is transient/cleanable, not permanent loss.
        #expect(BookAssetFailureClassifier.classify(BookAssetError.staleTransaction) == .retryable)
        let unreadable = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError
        )
        #expect(BookAssetFailureClassifier.classify(unreadable) == .retryable)
    }

    @Test func compareIOFailureThrowsInsteadOfAcceptingConflict() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let present = root.appendingPathComponent("present.epub")
        try Data("book".utf8).write(to: present)

        #expect(throws: (any Error).self) {
            _ = try BookAssetStaging.filesMatch(present, root.appendingPathComponent("missing.epub"))
        }
    }

    @Test func relaunchRollsBackFinalizedProvisionalAsset() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("download.epub")
        try Data("provisional".utf8).write(to: source)
        let identity = try BookAssetStaging.sha256(of: source)
        let destination = root.appendingPathComponent("Books/\(identity).epub")
        let provisionalURL = root.appendingPathComponent("provisional", isDirectory: true)
        let provisional = ProvisionalBookAssetStore(rootURL: provisionalURL)
        let transactionID = try provisional.prepare(
            files: BookAssetURLs(epub: source, cover: nil),
            identity: identity,
            epubDestination: destination,
            coverDestination: nil
        )
        _ = try provisional.finalize(transactionID)
        #expect(FileManager.default.fileExists(atPath: destination.path))

        _ = ProvisionalBookAssetStore(rootURL: provisionalURL)

        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func rollbackFailureRetainsJournalUntilCleanupSucceeds() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("download.epub")
        try Data("rollback failure".utf8).write(to: source)
        let identity = try BookAssetStaging.sha256(of: source)
        let destination = root.appendingPathComponent("Books/\(identity).epub")
        let provisionalURL = root.appendingPathComponent("provisional", isDirectory: true)
        let provisional = ProvisionalBookAssetStore(
            rootURL: provisionalURL,
            removeItem: { url in
                if url == destination { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.removeItem(at: url)
            }
        )
        let transactionID = try provisional.prepare(
            files: BookAssetURLs(epub: source, cover: nil),
            identity: identity,
            epubDestination: destination,
            coverDestination: nil
        )
        _ = try provisional.finalize(transactionID)

        #expect(throws: (any Error).self) { try provisional.rollback(transactionID) }
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(FileManager.default.fileExists(atPath: provisionalURL.appendingPathComponent(transactionID).path))

        _ = ProvisionalBookAssetStore(rootURL: provisionalURL)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func committedJournalNeverRollsBackValidBookOnRelaunch() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("download.epub")
        try Data("committed".utf8).write(to: source)
        let identity = try BookAssetStaging.sha256(of: source)
        let destination = root.appendingPathComponent("Books/\(identity).epub")
        let provisionalURL = root.appendingPathComponent("provisional", isDirectory: true)
        var transactionID: String?
        let provisional = ProvisionalBookAssetStore(
            rootURL: provisionalURL,
            removeItem: { url in
                if url.lastPathComponent == transactionID { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.removeItem(at: url)
            }
        )
        transactionID = try provisional.prepare(
            files: BookAssetURLs(epub: source, cover: nil),
            identity: identity,
            epubDestination: destination,
            coverDestination: nil
        )
        let committedID = try #require(transactionID)
        _ = try provisional.finalize(committedID)
        try provisional.commit(committedID)
        #expect(FileManager.default.fileExists(atPath: destination.path))

        _ = ProvisionalBookAssetStore(rootURL: provisionalURL)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func launchRemovesStaleTransferDirectories() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stagingRoot = root.appendingPathComponent("staging")
        let stale = stagingRoot.appendingPathComponent("upload-stale/book.epub")
        try FileManager.default.createDirectory(at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: stale)

        let staging = BookAssetStaging(rootURL: stagingRoot)
        staging.clearStaleFiles()

        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-assets-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Suite("Durable book asset transfer state")
struct DurableBookAssetTransferStateTests {
    @Test func transitionAssetsSurviveStateReloadAndCleanup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-transition-assets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = BookAssetStaging(rootURL: root.appendingPathComponent("staging"))
        let source = root.appendingPathComponent("book.epub")
        try Data("transition".utf8).write(to: source)
        let identity = try BookAssetStaging.sha256(of: source)
        let files = try staging.stageDownload(BookAssetURLs(epub: source, cover: nil), recordName: identity)
        let stale = try staging.stageDownload(BookAssetURLs(epub: source, cover: nil), recordName: "stale")
        var snapshot = SyncStateSnapshot.empty
        snapshot.accountTransitionRemoteAssets[identity] = AccountOwnedBookAssets(
            accountRecordName: "account-a",
            transitionGeneration: 2,
            files: files
        )
        let stateURL = root.appendingPathComponent("state.json")
        try SyncStateStore(fileURL: stateURL).save(snapshot)

        let restored = try SyncStateStore(fileURL: stateURL).load()
        let retainedURL = try #require(restored.accountTransitionRemoteAssets[identity]?.files.epub)
        let staleURL = try #require(stale.epub)
        staging.clearStaleFiles(retaining: [retainedURL])

        #expect(FileManager.default.fileExists(atPath: retainedURL.path))
        #expect(!FileManager.default.fileExists(atPath: staleURL.path))
    }

    @Test func transitionPolicyCarriesAssetsOnlyForAppliedBooks() throws {
        let keptIdentity = String(repeating: "a", count: 64)
        let deletedIdentity = String(repeating: "b", count: 64)
        let kept = LibraryRecord.book(book(identity: keptIdentity))
        let deleted = LibraryRecord.book(book(identity: deletedIdentity))
        let changes = AccountTransitionRemoteReconciler.changes(
            records: [kept, deleted],
            deletions: [],
            policy: .keepLocalAndUploadAfterFetch,
            initialLocalRecords: [],
            quarantinedSaves: [],
            quarantinedDeletes: [deleted.reference]
        )
        let files = BookAssetURLs(epub: URL(fileURLWithPath: "/tmp/book.epub"), cover: nil)
        let assetChanges = AccountTransitionRemoteReconciler.assetChanges(
            for: changes,
            stagedAssets: [keptIdentity: files, deletedIdentity: files]
        )

        #expect(assetChanges == [.bookAssets(contentIdentity: keptIdentity, files: files)])
    }

    @Test func downloadStageFailurePersistsRetryLedger() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-download-retry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stateURL = root.appendingPathComponent("state.json")
        let identity = String(repeating: "c", count: 64)
        var snapshot = SyncStateSnapshot.empty
        snapshot.recordAssetFailure(.retryable, recordName: identity, requiresDownloadRetry: true)
        try SyncStateStore(fileURL: stateURL).save(snapshot)

        let restored = try SyncStateStore(fileURL: stateURL).load()
        #expect(restored.bookAssetFailures[identity] == .retryable)
        #expect(restored.assetDownloadRetryRecordNames.contains(identity))
    }

    @Test func accountOwnedAssetsRejectAnotherAccountOrGeneration() {
        let owned = AccountOwnedBookAssets(
            accountRecordName: "account-a",
            transitionGeneration: 4,
            files: BookAssetURLs(epub: URL(fileURLWithPath: "/tmp/book.epub"), cover: nil)
        )

        #expect(owned.belongs(to: "account-a", generation: 4))
        #expect(!owned.belongs(to: "account-b", generation: 4))
        #expect(!owned.belongs(to: "account-a", generation: 5))
    }

    @Test func assetOutcomesRetainRetryAndDrainOnlyAfterSuccess() {
        let identity = String(repeating: "d", count: 64)
        let files = BookAssetURLs(epub: URL(fileURLWithPath: "/tmp/retry.epub"), cover: nil)
        let owned = AccountOwnedBookAssets(
            accountRecordName: "account-a",
            transitionGeneration: 1,
            files: files
        )
        var snapshot = SyncStateSnapshot.empty
        snapshot.pendingRemoteAssets[identity] = owned
        snapshot.recordAssetFailure(.retryable, recordName: identity, requiresDownloadRetry: true)

        _ = snapshot.recordAssetOutcome(.retryableFailure, recordName: identity, assets: owned)
        #expect(snapshot.pendingRemoteAssets[identity] == owned)
        #expect(snapshot.assetDownloadRetryRecordNames.contains(identity))

        _ = snapshot.recordAssetOutcome(
            .applied(createdEPUB: true, createdCover: false),
            recordName: identity,
            assets: owned
        )
        #expect(snapshot.pendingRemoteAssets[identity] == nil)
        #expect(!snapshot.assetDownloadRetryRecordNames.contains(identity))
        #expect(snapshot.bookAssetFailures[identity] == nil)
    }

    @Test func retryQueueCoalescesWhileOneDrainOwnsTheEngine() {
        var queue = BookAssetRetryQueue()
        let ownsDrain = queue.enqueue("book-a")
        let coalesced = queue.enqueue("book-b")
        #expect(ownsDrain)
        #expect(!coalesced)
        #expect(queue.takeNext() == ["book-a", "book-b"])
        #expect(queue.isDraining)
        queue.finish()
        #expect(!queue.isDraining)
    }

    @Test func transitionBlockedRetryRemainsQueuedForConfirmationResume() {
        var queue = BookAssetRetryQueue()
        let ownsInitialDrain = queue.enqueue("book-a")
        #expect(ownsInitialDrain)
        queue.finish()
        #expect(queue.queued == ["book-a"])

        let ownsResumedDrain = queue.enqueue("book-a")
        #expect(ownsResumedDrain)
        #expect(queue.takeNext() == ["book-a"])
    }

    @Test func durableAssetFailuresPreventIdleStatus() {
        #expect(BookAssetSyncStatusResolver.status(for: ["book": .retryable]) == .waitingToRetry(nil))
        #expect(BookAssetSyncStatusResolver.status(for: ["book": .corrupt]) == .blocked(.missingLocalData))
        #expect(BookAssetSyncStatusResolver.status(for: ["book": .blocked]) == .blocked(.quotaExceeded))
        #expect(BookAssetSyncStatusResolver.status(for: [:]) == .idle)
    }

    @Test func quotaExceededMapsToBlockedAndNeverRetryDrivesTheLedger() {
        let error = CKError(_nsError: NSError(
            domain: CKErrorDomain,
            code: CKError.Code.quotaExceeded.rawValue
        ))
        #expect(CloudKitErrorClassifier.classify(error) == .quotaExceeded)

        // A permanent quota failure records .blocked WITHOUT a download-retry
        // marker, so resumeDurableAssetRetries won't re-drive it into a loop.
        let identity = String(repeating: "f", count: 64)
        var snapshot = SyncStateSnapshot.empty
        snapshot.recordAssetFailure(.blocked, recordName: identity, requiresDownloadRetry: false)
        #expect(snapshot.assetDownloadRetryRecordNames.isEmpty)
        #expect(BookAssetSyncStatusResolver.status(for: snapshot.bookAssetFailures) == .blocked(.quotaExceeded))
    }

    @Test func retryNetworkErrorRemainsDurableAndRetryable() {
        let error = CKError(_nsError: NSError(
            domain: CKErrorDomain,
            code: CKError.Code.networkFailure.rawValue
        ))
        guard case .retryable = CloudKitErrorClassifier.classify(error) else {
            Issue.record("Expected retryable CloudKit failure")
            return
        }
        let identity = String(repeating: "e", count: 64)
        var snapshot = SyncStateSnapshot.empty
        snapshot.recordAssetFailure(.retryable, recordName: identity, requiresDownloadRetry: true)
        #expect(snapshot.assetDownloadRetryRecordNames == [identity])
        #expect(BookAssetSyncStatusResolver.status(for: snapshot.bookAssetFailures) == .waitingToRetry(nil))
    }

    private func book(identity: String) -> SyncedBook {
        SyncedBook(
            id: UUID(),
            contentIdentity: identity,
            title: "Book",
            author: "Author",
            originalExtension: "epub",
            hasCover: false,
            modifiedAt: .now
        )
    }
}

@Suite("BookStore asset lifecycle")
struct BookStoreAssetLifecycleTests {
    @Test @MainActor func metadataOnlyBookIsRemoteOnlyAndCanRetry() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let identity = String(repeating: "a", count: 64)
        fixture.applyBook(identity: identity)
        let book = try #require(fixture.store.books.first)

        #expect(fixture.store.assetAvailability(for: book) == .remoteOnly)
        fixture.store.retryAssets(for: book)
        #expect(fixture.store.assetAvailability(for: book) == .downloading)
        #expect(fixture.sync.assetRequests() == [identity])
    }

    @Test @MainActor func verifiedDownloadEvictionAndDeletionHaveSeparateMeaning() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let temporary = fixture.root.appendingPathComponent("download.epub")
        try Data("book data".utf8).write(to: temporary)
        let identity = try BookAssetStaging.sha256(of: temporary)
        fixture.applyBook(identity: identity)
        let prepared = fixture.store.applyRemoteChanges([
            .bookAssets(contentIdentity: identity, files: BookAssetURLs(epub: temporary, cover: nil)),
        ])
        guard case .provisional(let transactionID) = prepared.assetOutcomes[identity] else {
            Issue.record("Expected provisional download")
            return
        }
        let book = try #require(fixture.store.books.first)
        #expect(fixture.store.localBookAssets(for: syncedBook(book)) == nil)
        _ = fixture.store.applyRemoteChanges([
            .finalizeBookAssets(contentIdentity: identity, transactionID: transactionID),
            .commitBookAssets(contentIdentity: identity, transactionID: transactionID),
        ])
        #expect(fixture.store.assetAvailability(for: book) == .local)

        fixture.store.evictAssets(for: book)
        #expect(fixture.store.books.count == 1)
        #expect(fixture.store.assetAvailability(for: book) == .remoteOnly)

        fixture.store.deleteBook(book)
        #expect(fixture.store.books.isEmpty)
        #expect(fixture.sync.snapshot().deleted.contains(bookReference(identity)))
    }

    @Test @MainActor func evictionIsRefusedWhileBookIsActivelyRead() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let temporary = fixture.root.appendingPathComponent("open.epub")
        try Data("book data".utf8).write(to: temporary)
        let identity = try BookAssetStaging.sha256(of: temporary)
        fixture.applyBook(identity: identity)
        let prepared = fixture.store.applyRemoteChanges([
            .bookAssets(contentIdentity: identity, files: BookAssetURLs(epub: temporary, cover: nil)),
        ])
        guard case .provisional(let transactionID) = prepared.assetOutcomes[identity] else {
            Issue.record("Expected provisional download")
            return
        }
        _ = fixture.store.applyRemoteChanges([
            .finalizeBookAssets(contentIdentity: identity, transactionID: transactionID),
            .commitBookAssets(contentIdentity: identity, transactionID: transactionID),
        ])
        let book = try #require(fixture.store.books.first)
        #expect(fixture.store.assetAvailability(for: book) == .local)

        fixture.store.beginReading(book)
        fixture.store.evictAssets(for: book)
        // File must survive so Readium's open handle stays valid.
        #expect(FileManager.default.fileExists(atPath: fixture.store.bookURL(for: book).path))
        #expect(fixture.store.assetAvailability(for: book) == .local)

        fixture.store.endReading(book)
        fixture.store.evictAssets(for: book)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.bookURL(for: book).path))
        #expect(fixture.store.assetAvailability(for: book) == .remoteOnly)
    }

    @Test @MainActor func corruptDownloadIsUnavailableAndLocalFileLossRecoversAsRemoteOnly() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let identity = String(repeating: "b", count: 64)
        fixture.applyBook(identity: identity)
        let corrupt = fixture.root.appendingPathComponent("corrupt.epub")
        try Data("not matching".utf8).write(to: corrupt)
        _ = fixture.store.applyRemoteChanges([
            .bookAssets(contentIdentity: identity, files: BookAssetURLs(epub: corrupt, cover: nil)),
        ])
        let book = try #require(fixture.store.books.first)
        #expect(fixture.store.assetAvailability(for: book) == .unavailable)

        fixture.store.saveBooks()
        let restarted = fixture.makeStore()
        let restartedBook = try #require(restarted.books.first)
        #expect(restarted.assetAvailability(for: restartedBook) == .remoteOnly)
    }

    @Test @MainActor func generationRollbackRemovesOnlyNewlyPublishedAsset() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let downloaded = fixture.root.appendingPathComponent("owned.epub")
        try Data("owned account bytes".utf8).write(to: downloaded)
        let identity = try BookAssetStaging.sha256(of: downloaded)
        fixture.applyBook(identity: identity)

        let result = fixture.store.applyRemoteChanges([
            .bookAssets(contentIdentity: identity, files: BookAssetURLs(epub: downloaded, cover: nil)),
        ])
        guard case .provisional(let transactionID) = result.assetOutcomes[identity] else {
            Issue.record("Expected a provisional asset transaction")
            return
        }
        let finalized = fixture.store.applyRemoteChanges([
            .finalizeBookAssets(contentIdentity: identity, transactionID: transactionID),
        ])
        #expect(finalized.assetOutcomes[identity] == .applied(createdEPUB: true, createdCover: false))
        let book = try #require(fixture.store.books.first)
        #expect(fixture.store.localBookAssets(for: syncedBook(book))?.epub != nil)

        _ = fixture.store.applyRemoteChanges([
            .rollbackBookAssets(contentIdentity: identity, transactionID: transactionID),
        ])
        #expect(fixture.store.localBookAssets(for: syncedBook(book)) == nil)
        #expect(fixture.store.assetAvailability(for: book) == .remoteOnly)
    }

    private func bookReference(_ identity: String) -> LibraryRecordReference {
        LibraryRecordReference(recordType: "Book", recordName: identity)
    }

    private func syncedBook(_ book: Book) -> SyncedBook {
        SyncedBook(
            id: book.id,
            contentIdentity: book.contentIdentity,
            title: book.title,
            author: book.author,
            originalExtension: "epub",
            hasCover: false,
            modifiedAt: book.modifiedAt
        )
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let defaults: UserDefaults
        let suiteName: String
        let sync = FakeLibrarySync()
        let store: BookStore

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("piperly-store-assets-\(UUID().uuidString)", isDirectory: true)
            suiteName = "PiperlyTests.Assets.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            store = BookStore(
                documentsURL: root.appendingPathComponent("Books", isDirectory: true),
                coversURL: root.appendingPathComponent("Covers", isDirectory: true),
                userDefaults: defaults,
                librarySync: sync
            )
        }

        func makeStore() -> BookStore {
            BookStore(
                documentsURL: root.appendingPathComponent("Books", isDirectory: true),
                coversURL: root.appendingPathComponent("Covers", isDirectory: true),
                userDefaults: defaults,
                librarySync: sync
            )
        }

        func applyBook(identity: String) {
            _ = store.applyRemoteChanges([.save(.book(SyncedBook(
                id: UUID(),
                contentIdentity: identity,
                title: "Remote",
                author: "Author",
                originalExtension: "epub",
                hasCover: false,
                modifiedAt: .now
            )))])
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
