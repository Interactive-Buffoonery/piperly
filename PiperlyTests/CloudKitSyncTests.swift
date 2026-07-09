import CloudKit
import Foundation
import Testing
@testable import Piperly

@Suite("CloudKit record codec")
struct CloudKitRecordCodecTests {
    private let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let bookIdentity = String(repeating: "a", count: 64)
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func deterministicRecordNamesContainNoUserContent() {
        let book = LibraryRecord.book(SyncedBook(
            id: UUID(),
            contentIdentity: bookIdentity.uppercased(),
            title: "A Child's Book",
            author: "Private Author",
            originalExtension: "epub",
            hasCover: true,
            modifiedAt: date
        ))
        let reading = LibraryRecord.readingState(SyncedReadingState(
            profileID: profileID,
            bookIdentity: bookIdentity,
            progression: 0.5,
            locatorJSON: nil,
            modifiedAt: date
        ))

        #expect(book.reference.recordName == bookIdentity)
        #expect(reading.reference.recordName == "reading-\(profileID.uuidString.lowercased())-\(bookIdentity)")
        #expect(!book.reference.recordName.contains("Child"))
    }

    @Test func allMetadataRecordsRoundTrip() throws {
        let records: [LibraryRecord] = [
            .book(SyncedBook(
                id: UUID(),
                contentIdentity: bookIdentity,
                title: "The Book",
                author: "An Author",
                originalExtension: "epub",
                hasCover: true,
                modifiedAt: date
            )),
            .readerProfile(SyncedReaderProfile(
                id: profileID,
                nickname: "Ari",
                avatarSymbol: "star.fill",
                colorName: "yellow",
                createdAt: date,
                modifiedAt: date
            )),
            .readerPreferences(SyncedReaderPreferences(
                profileID: profileID,
                voiceIdentifier: "voice",
                speechRate: 0.45,
                fontSize: 22,
                readerTheme: "piperly",
                hasCompletedVoiceSetup: true,
                modifiedAt: date
            )),
            .readingState(SyncedReadingState(
                profileID: profileID,
                bookIdentity: bookIdentity,
                progression: 0.75,
                locatorJSON: "{\"href\":\"chapter-2\"}",
                modifiedAt: date
            )),
            .bookmark(SyncedBookmark(
                id: UUID(),
                profileID: profileID,
                bookIdentity: bookIdentity,
                locatorJSON: "{}",
                title: "Chapter 2",
                progression: 0.4,
                sticker: "star",
                createdAt: date,
                modifiedAt: date
            )),
            .savedWord(SyncedSavedWord(
                id: UUID(),
                profileID: profileID,
                bookIdentity: bookIdentity,
                canonicalWord: "wonder",
                displayWord: "Wonder",
                bookTitle: "The Book",
                tapCount: 3,
                savedAt: date,
                lastTappedAt: date,
                modifiedAt: date
            )),
        ]

        for value in records {
            let cloudRecord = try LibraryRecordCodec.encode(value)
            #expect(try LibraryRecordCodec.decode(cloudRecord) == value)
            #expect(cloudRecord.recordID.zoneID == LibraryRecordCodec.zoneID)
        }
    }

    @Test func systemFieldsPreserveRecordIdentity() throws {
        let value = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: profileID,
            nickname: "Ari",
            avatarSymbol: "star.fill",
            colorName: "yellow",
            createdAt: date,
            modifiedAt: date
        ))
        let first = try LibraryRecordCodec.encode(value)
        let data = LibraryRecordCodec.systemFieldsData(for: first)
        let second = try LibraryRecordCodec.encode(value, systemFields: data)
        #expect(second.recordID == first.recordID)
        #expect(second.recordType == first.recordType)
    }
}

@Suite("CloudKit conflict resolution")
struct CloudKitConflictTests {
    @Test func savedWordCombinesCountersAndDates() {
        let id = UUID()
        let profileID = UUID()
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)
        let local = SyncedSavedWord(
            id: id,
            profileID: profileID,
            bookIdentity: "hash",
            canonicalWord: "word",
            displayWord: "WORD",
            bookTitle: "Old",
            tapCount: 8,
            savedAt: late,
            lastTappedAt: early,
            modifiedAt: early
        )
        let remote = SyncedSavedWord(
            id: id,
            profileID: profileID,
            bookIdentity: "hash",
            canonicalWord: "word",
            displayWord: "Word",
            bookTitle: "New",
            tapCount: 3,
            savedAt: early,
            lastTappedAt: late,
            modifiedAt: late
        )

        guard case .savedWord(let merged) = LibraryConflictResolver.merge(
            local: .savedWord(local),
            remote: .savedWord(remote)
        ) else {
            Issue.record("Expected a saved-word merge")
            return
        }
        #expect(merged.tapCount == 8)
        #expect(merged.savedAt == early)
        #expect(merged.lastTappedAt == late)
        #expect(merged.displayWord == "Word")
    }

    @Test func readingStateKeepsLocatorAndProgressionTogether() {
        let local = SyncedReadingState(
            profileID: UUID(),
            bookIdentity: "hash",
            progression: 0.2,
            locatorJSON: "local",
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let remote = SyncedReadingState(
            profileID: local.profileID,
            bookIdentity: "hash",
            progression: 0.8,
            locatorJSON: "remote",
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        guard case .readingState(let merged) = LibraryConflictResolver.merge(
            local: .readingState(local),
            remote: .readingState(remote)
        ) else {
            Issue.record("Expected a reading-state merge")
            return
        }
        #expect(merged.progression == 0.8)
        #expect(merged.locatorJSON == "remote")
    }
}

@Suite("CloudKit durable queue")
struct CloudKitStateStoreTests {
    @Test func pendingWorkSurvivesReload() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-sync-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = SyncStateStore(fileURL: fileURL)
        let record = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: UUID(),
            nickname: "Ari",
            avatarSymbol: "star.fill",
            colorName: "yellow",
            createdAt: .now,
            modifiedAt: .now
        ))
        let deletion = LibraryRecordReference(
            recordType: "Bookmark",
            recordName: "bookmark-\(UUID().uuidString.lowercased())"
        )
        var snapshot = SyncStateSnapshot.empty
        snapshot.pendingSaves[record.reference.recordName] = record
        snapshot.pendingDeletes = [deletion]
        snapshot.deferredRemoteRecords[record.reference.recordName] = record
        try store.save(snapshot)

        let loaded = try store.load()
        #expect(loaded.pendingSaves[record.reference.recordName] == record)
        #expect(loaded.pendingDeletes == [deletion])
        #expect(loaded.deferredRemoteRecords[record.reference.recordName] == record)
    }
}

@Suite("CloudKit error classification")
struct CloudKitErrorClassificationTests {
    @Test func networkFailuresRemainRetryable() {
        let error = CKError(_nsError: NSError(
            domain: CKErrorDomain,
            code: CKError.Code.networkUnavailable.rawValue
        ))
        guard case .retryable = CloudKitErrorClassifier.classify(error) else {
            Issue.record("Expected a retryable failure")
            return
        }
    }

    @Test func quotaAndPermissionFailuresBlockSync() {
        let quota = CKError(_nsError: NSError(
            domain: CKErrorDomain,
            code: CKError.Code.quotaExceeded.rawValue
        ))
        let permission = CKError(_nsError: NSError(
            domain: CKErrorDomain,
            code: CKError.Code.permissionFailure.rawValue
        ))
        #expect(CloudKitErrorClassifier.classify(quota) == .quotaExceeded)
        #expect(CloudKitErrorClassifier.classify(permission) == .permissionDenied)
    }
}

@Suite("BookStore sync boundary")
struct BookStoreSyncBoundaryTests {
    @Test @MainActor func applyingRemoteChangesDoesNotRequeueThem() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "PiperlyTests.Sync.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sync = FakeLibrarySync()
        let store = BookStore(
            documentsURL: root.appendingPathComponent("Books", isDirectory: true),
            coversURL: root.appendingPathComponent("Covers", isDirectory: true),
            userDefaults: defaults,
            librarySync: sync
        )
        let record = LibraryRecord.book(SyncedBook(
            id: UUID(),
            contentIdentity: String(repeating: "b", count: 64),
            title: "Remote Book",
            author: "Remote Author",
            originalExtension: "epub",
            hasCover: false,
            modifiedAt: .now
        ))

        _ = store.applyRemoteChanges([.save(record)])
        await Task.yield()
        let queued = sync.snapshot()
        #expect(queued.saved.isEmpty)
        #expect(queued.deleted.isEmpty)
        #expect(store.books.count == 1)
    }
}

@Suite("CloudKit sync correctness regressions")
struct CloudKitSyncCorrectnessTests {
    @Test func corruptOutboxBlocksWithoutOverwritingQueueFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-corrupt-outbox-\(UUID().uuidString).json")
        let corruptData = Data("not valid json".utf8)
        try corruptData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let router = LibrarySyncRouter(fileURL: fileURL)
        let record = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: UUID(),
            nickname: "Ari",
            avatarSymbol: "star.fill",
            colorName: "yellow",
            createdAt: .now,
            modifiedAt: .now
        ))

        #expect(router.outboxStatus() == .blocked)
        #expect(throws: LibraryOutboxError.self) {
            try router.enqueueSave(record)
        }
        #expect(try Data(contentsOf: fileURL) == corruptData)
    }

    @Test func localOutboxPersistsTheLastIntentSynchronously() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-outbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let router = LibrarySyncRouter(fileURL: fileURL)
        let record = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: UUID(),
            nickname: "Ari",
            avatarSymbol: "star.fill",
            colorName: "yellow",
            createdAt: .now,
            modifiedAt: .now
        ))

        try router.enqueueSave(record)
        try router.enqueueDelete(record.reference)
        try router.flush()

        let persisted = try LibraryOutboxStore(fileURL: fileURL).load()
        #expect(persisted == [.delete(record.reference)])
        let relaunched = LibrarySyncRouter(fileURL: fileURL)
        #expect(relaunched.pendingOperations() == persisted)
    }

    @Test func fetchedSaveCannotBeatPendingTombstone() {
        let reference = LibraryRecordReference(
            recordType: "Bookmark",
            recordName: "bookmark-\(UUID().uuidString.lowercased())"
        )
        #expect(FetchedRecordReconciler.isTombstoned(
            reference,
            pendingDeletes: [reference],
            quarantinedDeletes: []
        ))
        #expect(FetchedRecordReconciler.isTombstoned(
            reference,
            pendingDeletes: [],
            quarantinedDeletes: [reference]
        ))
    }

    @Test @MainActor func sameHashBookMergeKeepsLocalIdentityAndChildren() throws {
        let fixture = try storeFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let localID = UUID()
        let remoteID = UUID()
        let identity = String(repeating: "c", count: 64)
        store.books = [Book(
            id: localID,
            contentIdentity: identity,
            title: "Local",
            author: "Author",
            fileName: "\(identity).epub",
            modifiedAt: Date(timeIntervalSince1970: 100)
        )]
        store.readingStates = [ReadingState(profileID: store.activeProfile.id, bookID: localID)]
        _ = store.applyRemoteChanges([.save(.book(SyncedBook(
            id: remoteID,
            contentIdentity: identity,
            title: "Remote",
            author: "Author",
            originalExtension: "epub",
            hasCover: false,
            modifiedAt: Date(timeIntervalSince1970: 200)
        )))])

        #expect(store.books.first?.id == localID)
        #expect(store.readingStates.first?.bookID == localID)
        #expect(store.books.first?.title == "Remote")
    }

    @Test func accountChangeQuarantinesWorkUntilExplicitPolicy() {
        let record = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: UUID(),
            nickname: "Ari",
            avatarSymbol: "star.fill",
            colorName: "yellow",
            createdAt: .now,
            modifiedAt: .now
        ))
        var snapshot = SyncStateSnapshot.empty
        snapshot.pendingSaves[record.reference.recordName] = record
        SyncAccountTransition.quarantine(snapshot: &snapshot)
        #expect(snapshot.pendingSaves.isEmpty)
        #expect(snapshot.quarantinedSaves[record.reference.recordName] == record)

        var discard = snapshot
        SyncAccountTransition.resolve(policy: .discardPendingChanges, snapshot: &discard)
        #expect(discard.pendingSaves.isEmpty)
        #expect(discard.quarantinedSaves.isEmpty)

        SyncAccountTransition.resolve(policy: .keepLocalAndUploadAfterFetch, snapshot: &snapshot)
        #expect(snapshot.pendingSaves[record.reference.recordName] == record)
        #expect(snapshot.quarantinedSaves.isEmpty)
    }

    @Test func confirmationRejectsAnAccountThatChangedDuringFetch() {
        #expect(throws: SyncAccountTransitionError.accountChangedDuringConfirmation) {
            try SyncAccountTransitionValidator.validate(
                initialRecordName: "first-account",
                verifiedRecordName: "second-account"
            )
        }
        #expect(throws: SyncAccountTransitionError.accountChangedDuringConfirmation) {
            try SyncAccountTransitionValidator.validateGeneration(
                expected: 7,
                current: 8,
                isTransitionActive: true
            )
        }
        #expect(throws: SyncAccountTransitionError.accountChangedDuringConfirmation) {
            try SyncAccountTransitionValidator.validateGeneration(
                expected: 7,
                current: 7,
                isTransitionActive: false
            )
        }
    }

    @Test func initialLibrarySeedsExactlyOnceAcrossRelaunch() throws {
        let record = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: UUID(),
            nickname: "Ari",
            avatarSymbol: "star.fill",
            colorName: "yellow",
            createdAt: .now,
            modifiedAt: .now
        ))
        var snapshot = SyncStateSnapshot.empty
        SyncInitialLibrarySeeder.seedIfNeeded(
            records: [record],
            policy: .keepLocalAndUploadAfterFetch,
            snapshot: &snapshot
        )
        #expect(snapshot.pendingSaves[record.reference.recordName] == record)
        snapshot.pendingSaves = [:]

        let relaunched = try JSONDecoder().decode(
            SyncStateSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        var afterRelaunch = relaunched
        SyncInitialLibrarySeeder.seedIfNeeded(
            records: [record],
            policy: .keepLocalAndUploadAfterFetch,
            snapshot: &afterRelaunch
        )
        #expect(afterRelaunch.didSeedExistingLibrary)
        #expect(afterRelaunch.pendingSaves.isEmpty)
    }

    @Test func fetchedDeletionDoesNotMutateQuarantinedChoice() {
        let record = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: UUID(),
            nickname: "Ari",
            avatarSymbol: "star.fill",
            colorName: "yellow",
            createdAt: .now,
            modifiedAt: .now
        ))
        var snapshot = SyncStateSnapshot.empty
        snapshot.quarantinedSaves[record.reference.recordName] = record
        let originalSaves = snapshot.quarantinedSaves
        let originalDeletes = snapshot.quarantinedDeletes

        FetchedRecordReconciler.applyRemoteDeletion(record.reference, snapshot: &snapshot)

        #expect(snapshot.quarantinedSaves == originalSaves)
        #expect(snapshot.quarantinedDeletes == originalDeletes)
    }

    @Test func keepLocalSuppressesFetchedDeletionBeforeInitialSeed() {
        let book = LibraryRecord.book(SyncedBook(
            id: UUID(),
            contentIdentity: String(repeating: "e", count: 64),
            title: "Local Book",
            author: "Author",
            originalExtension: "epub",
            hasCover: true,
            modifiedAt: .now
        ))
        let keepChanges = AccountTransitionRemoteReconciler.changes(
            records: [],
            deletions: [book.reference],
            policy: .keepLocalAndUploadAfterFetch,
            initialLocalRecords: [book],
            quarantinedSaves: [],
            quarantinedDeletes: []
        )
        let discardChanges = AccountTransitionRemoteReconciler.changes(
            records: [],
            deletions: [book.reference],
            policy: .discardPendingChanges,
            initialLocalRecords: [book],
            quarantinedSaves: [],
            quarantinedDeletes: []
        )

        #expect(keepChanges.isEmpty)
        #expect(discardChanges == [.delete(book.reference)])
    }

    @Test func keepLocalSuppressesFetchedDeletionForQuarantinedSave() {
        let profile = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: UUID(),
            nickname: "Ari",
            avatarSymbol: "star.fill",
            colorName: "yellow",
            createdAt: .now,
            modifiedAt: .now
        ))
        let changes = AccountTransitionRemoteReconciler.changes(
            records: [],
            deletions: [profile.reference],
            policy: .keepLocalAndUploadAfterFetch,
            initialLocalRecords: [],
            quarantinedSaves: [profile],
            quarantinedDeletes: []
        )
        #expect(changes.isEmpty)
    }

    @Test @MainActor func keepLocalSeedsPostMergeSnapshotInsteadOfStaleCapture() throws {
        let fixture = try storeFixture()
        defer { fixture.cleanUp() }
        let identity = String(repeating: "f", count: 64)
        let localBook = Book(
            contentIdentity: identity,
            title: "Older Local Title",
            author: "Author",
            fileName: "\(identity).epub",
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        fixture.store.books = [localBook]
        let staleCapture = fixture.store.librarySnapshotRecords()
        _ = fixture.store.applyRemoteChanges([.save(.book(SyncedBook(
            id: UUID(),
            contentIdentity: identity,
            title: "Newer Remote Title",
            author: "Author",
            originalExtension: "epub",
            hasCover: false,
            modifiedAt: Date(timeIntervalSince1970: 200)
        )))])
        let postMergeSnapshot = fixture.store.librarySnapshotRecords()
        var snapshot = SyncStateSnapshot.empty
        SyncInitialLibrarySeeder.seedIfNeeded(
            records: postMergeSnapshot,
            policy: .keepLocalAndUploadAfterFetch,
            snapshot: &snapshot
        )

        let staleBook = try #require(staleCapture.first { $0.reference.recordName == identity })
        let seededBook = try #require(snapshot.pendingSaves[identity])
        guard case .book(let stale) = staleBook, case .book(let seeded) = seededBook else {
            Issue.record("Expected book snapshots")
            return
        }
        #expect(stale.title == "Older Local Title")
        #expect(seeded.title == "Newer Remote Title")
    }

    @Test func discardOldWorkStillCommitsCurrentAccountReplacement() {
        let oldProfile = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: UUID(),
            nickname: "Old",
            avatarSymbol: "person.fill",
            colorName: "blue",
            createdAt: .now,
            modifiedAt: .now
        ))
        let replacement = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: UUID(),
            nickname: "Reader",
            avatarSymbol: "person.crop.circle.fill",
            colorName: "accent",
            createdAt: .now,
            modifiedAt: .now
        ))
        var snapshot = SyncStateSnapshot.empty
        snapshot.quarantinedSaves[oldProfile.reference.recordName] = oldProfile
        SyncCurrentAccountOperations.recordSave(
            replacement,
            accountRecordName: "account-a",
            transitionGeneration: 4,
            snapshot: &snapshot
        )

        SyncAccountTransition.resolve(policy: .discardPendingChanges, snapshot: &snapshot)
        let committed = SyncCurrentAccountOperations.commitIfMatching(
            accountRecordName: "account-a",
            transitionGeneration: 4,
            snapshot: &snapshot
        )

        #expect(committed)
        #expect(snapshot.pendingSaves[oldProfile.reference.recordName] == nil)
        #expect(snapshot.pendingSaves[replacement.reference.recordName] == replacement)
        #expect(snapshot.currentAccountSaves.isEmpty)
    }

    @Test func routerMarksStagedReplacementAsCurrentAccountWork() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-current-account-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let router = LibrarySyncRouter(fileURL: fileURL)
        let replacement = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: UUID(),
            nickname: "Reader",
            avatarSymbol: "person.crop.circle.fill",
            colorName: "accent",
            createdAt: .now,
            modifiedAt: .now
        ))
        let scope = RemoteApplicationScope.currentAccount(
            accountRecordName: "account-a",
            transitionGeneration: 3
        )
        var enqueueError: Error?
        _ = router.applyingCurrentAccountChanges(scope: scope) {
            do {
                try router.enqueueSave(replacement)
            } catch {
                enqueueError = error
            }
            return .complete
        }

        #expect(enqueueError == nil)
        #expect(router.pendingOperations().first?.effectiveScope == scope)
    }

    @Test func accountSwitchCannotCommitReplacementFromPreviousAccount() throws {
        let replacement = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: UUID(),
            nickname: "Reader",
            avatarSymbol: "person.crop.circle.fill",
            colorName: "accent",
            createdAt: .now,
            modifiedAt: .now
        ))
        var snapshot = SyncStateSnapshot.empty
        SyncCurrentAccountOperations.recordSave(
            replacement,
            accountRecordName: "account-a",
            transitionGeneration: 8,
            snapshot: &snapshot
        )
        let restored = try JSONDecoder().decode(
            SyncStateSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        snapshot = restored
        #expect(snapshot.currentAccountRecordName == "account-a")
        #expect(snapshot.currentAccountTransitionGeneration == 8)

        let committed = SyncCurrentAccountOperations.commitIfMatching(
            accountRecordName: "account-b",
            transitionGeneration: 9,
            snapshot: &snapshot
        )

        #expect(!committed)
        #expect(snapshot.pendingSaves[replacement.reference.recordName] == nil)
        #expect(snapshot.quarantinedSaves[replacement.reference.recordName] == replacement)
        #expect(snapshot.currentAccountSaves.isEmpty)
        #expect(snapshot.currentAccountRecordName == nil)
        #expect(snapshot.currentAccountTransitionGeneration == nil)
    }

    @Test func keepLocalRefreshesEstablishedLibrarySaveAfterRemoteMerge() {
        let identity = String(repeating: "e", count: 64)
        let stale = LibraryRecord.book(SyncedBook(
            id: UUID(),
            contentIdentity: identity,
            title: "Stale Local Title",
            author: "Author",
            originalExtension: "epub",
            hasCover: false,
            modifiedAt: Date(timeIntervalSince1970: 100)
        ))
        let merged = LibraryRecord.book(SyncedBook(
            id: UUID(),
            contentIdentity: identity,
            title: "Newer Remote Title",
            author: "Author",
            originalExtension: "epub",
            hasCover: false,
            modifiedAt: Date(timeIntervalSince1970: 200)
        ))
        var snapshot = SyncStateSnapshot.empty
        snapshot.didSeedExistingLibrary = true
        snapshot.quarantinedSaves[identity] = stale

        SyncAccountTransition.refreshQuarantinedSaves(from: [merged], snapshot: &snapshot)
        SyncAccountTransition.resolve(policy: .keepLocalAndUploadAfterFetch, snapshot: &snapshot)

        #expect(snapshot.pendingSaves[identity] == merged)
        #expect(snapshot.pendingSaves[identity] != stale)
    }

    @Test @MainActor func childRecordsDeferUntilParentsArrive() throws {
        let fixture = try storeFixture()
        defer { fixture.cleanUp() }
        let profileID = UUID()
        let bookID = UUID()
        let identity = String(repeating: "d", count: 64)
        let state = LibraryRecord.readingState(SyncedReadingState(
            profileID: profileID,
            bookIdentity: identity,
            progression: 0.7,
            locatorJSON: "{}",
            modifiedAt: .now
        ))
        let first = fixture.store.applyRemoteChanges([.save(state)])
        #expect(first.unresolvedRecords == [state])
        #expect(fixture.store.readingStates.isEmpty)

        let second = fixture.store.applyRemoteChanges([
            .save(.readerProfile(SyncedReaderProfile(
                id: profileID,
                nickname: "Ari",
                avatarSymbol: "star.fill",
                colorName: "yellow",
                createdAt: .now,
                modifiedAt: .now
            ))),
            .save(.book(SyncedBook(
                id: bookID,
                contentIdentity: identity,
                title: "Book",
                author: "Author",
                originalExtension: "epub",
                hasCover: false,
                modifiedAt: .now
            ))),
            .save(state),
        ])
        #expect(second.unresolvedRecords.isEmpty)
        #expect(fixture.store.readingStates.contains {
            $0.profileID == profileID && $0.bookID == bookID
        })
    }

    @Test func retryableSaveProducesAPendingSave() {
        let recordID = CKRecord.ID(
            recordName: "profile-\(UUID().uuidString.lowercased())",
            zoneID: LibraryRecordCodec.zoneID
        )
        let error = CKError(_nsError: NSError(
            domain: CKErrorDomain,
            code: CKError.Code.networkFailure.rawValue
        ))
        #expect(CloudKitRetryPolicy.pendingSave(recordID: recordID, error: error) == .saveRecord(recordID))
    }

    @Test @MainActor func deletingLastProfileCreatesAndQueuesFreshDefault() throws {
        let sync = FakeLibrarySync()
        let fixture = try storeFixture(sync: sync)
        defer { fixture.cleanUp() }
        let deletedID = fixture.store.activeProfile.id
        _ = fixture.store.applyRemoteChanges([.delete(LibraryRecordReference(
            recordType: "ReaderProfile",
            recordName: "profile-\(deletedID.uuidString.lowercased())"
        ))])

        #expect(fixture.store.profiles.count == 1)
        #expect(fixture.store.activeProfile.id != deletedID)
        let queued = sync.snapshot().saved
        #expect(queued.contains {
            guard case .readerProfile(let profile) = $0 else { return false }
            return profile.id == fixture.store.activeProfile.id
        })
    }

    @Test @MainActor func profileAndPreferencesUseIndependentClocks() throws {
        let fixture = try storeFixture()
        defer { fixture.cleanUp() }
        let profile = try ReaderProfile(
            id: UUID(),
            name: "Ari",
            voiceIdentifier: "old",
            metadataModifiedAt: Date(timeIntervalSince1970: 200),
            preferencesModifiedAt: Date(timeIntervalSince1970: 100)
        )
        fixture.store.profiles = [profile]
        fixture.store.selectedProfileID = profile.id

        _ = fixture.store.applyRemoteChanges([.save(.readerPreferences(SyncedReaderPreferences(
            profileID: profile.id,
            voiceIdentifier: "new",
            speechRate: 0.5,
            fontSize: 24,
            readerTheme: "paper",
            hasCompletedVoiceSetup: true,
            modifiedAt: Date(timeIntervalSince1970: 150)
        )))])
        #expect(fixture.store.activeProfile.voiceIdentifier == "new")
        #expect(fixture.store.activeProfile.metadataModifiedAt == Date(timeIntervalSince1970: 200))
        #expect(fixture.store.activeProfile.preferencesModifiedAt == Date(timeIntervalSince1970: 150))
    }

    @Test @MainActor func freshRemoteProfileAcceptsItsOlderPreferencesRecord() throws {
        let fixture = try storeFixture()
        defer { fixture.cleanUp() }
        let profileID = UUID()
        let result = fixture.store.applyRemoteChanges([
            .save(.readerProfile(SyncedReaderProfile(
                id: profileID,
                nickname: "Ari",
                avatarSymbol: "star.fill",
                colorName: "yellow",
                createdAt: Date(timeIntervalSince1970: 100),
                modifiedAt: Date(timeIntervalSince1970: 200)
            ))),
            .save(.readerPreferences(SyncedReaderPreferences(
                profileID: profileID,
                voiceIdentifier: "remote-voice",
                speechRate: 0.5,
                fontSize: 24,
                readerTheme: "paper",
                hasCompletedVoiceSetup: true,
                modifiedAt: Date(timeIntervalSince1970: 150)
            ))),
        ])

        #expect(result.unresolvedRecords.isEmpty)
        let profile = try #require(fixture.store.profiles.first { $0.id == profileID })
        #expect(profile.voiceIdentifier == "remote-voice")
        #expect(profile.preferencesModifiedAt == Date(timeIntervalSince1970: 150))
    }

    @Test @MainActor func failedOutboxSaveLeavesLocalProfileUnchanged() throws {
        let fixture = try storeFixture(sync: FailingLibrarySync())
        defer { fixture.cleanUp() }
        let originalProfiles = fixture.store.profiles

        #expect(throws: BookStoreError.self) {
            _ = try fixture.store.addProfile(name: "Ari", avatarSymbol: "star.fill", colorName: "yellow")
        }
        #expect(fixture.store.profiles == originalProfiles)
        #expect(fixture.store.syncOutboxStatus == .blocked)
    }

    @Test @MainActor func failedOutboxDeleteLeavesLocalProfileAndChildren() throws {
        let fixture = try storeFixture(sync: FailingLibrarySync())
        defer { fixture.cleanUp() }
        let first = fixture.store.activeProfile
        let second = try ReaderProfile(name: "Ari")
        fixture.store.profiles.append(second)
        let state = ReadingState(profileID: second.id, bookID: UUID())
        fixture.store.readingStates = [state]

        fixture.store.deleteProfile(second.id)

        #expect(fixture.store.profiles.contains { $0.id == first.id })
        #expect(fixture.store.profiles.contains { $0.id == second.id })
        #expect(fixture.store.readingStates == [state])
        #expect(fixture.store.syncOutboxStatus == .blocked)
    }

    @Test @MainActor func failedReplacementQueueKeepsLastDeletedProfileRecoverable() throws {
        let fixture = try storeFixture(sync: FailingLibrarySync())
        defer { fixture.cleanUp() }
        let original = fixture.store.activeProfile
        let deletion = LibraryRecordReference(
            recordType: "ReaderProfile",
            recordName: "profile-\(original.id.uuidString.lowercased())"
        )

        let result = fixture.store.applyRemoteChanges([.delete(deletion)])

        #expect(fixture.store.profiles == [original])
        #expect(result.unresolvedDeletions == [deletion])
        #expect(fixture.store.syncOutboxStatus == .blocked)
    }

    @Test func UUIDBackedRecordsUseOnePrefixedNamespace() {
        let sharedID = UUID()
        let profile = LibraryRecord.readerProfile(SyncedReaderProfile(
            id: sharedID,
            nickname: "Ari",
            avatarSymbol: "star.fill",
            colorName: "yellow",
            createdAt: .now,
            modifiedAt: .now
        ))
        let bookmark = LibraryRecord.bookmark(SyncedBookmark(
            id: sharedID,
            profileID: sharedID,
            bookIdentity: "hash",
            locatorJSON: "{}",
            title: nil,
            progression: 0,
            sticker: "star",
            createdAt: .now,
            modifiedAt: .now
        ))
        let word = LibraryRecord.savedWord(SyncedSavedWord(
            id: sharedID,
            profileID: sharedID,
            bookIdentity: "hash",
            canonicalWord: "word",
            displayWord: "Word",
            bookTitle: "Book",
            tapCount: 1,
            savedAt: .now,
            lastTappedAt: .now,
            modifiedAt: .now
        ))
        let names = Set([profile.reference.recordName, bookmark.reference.recordName, word.reference.recordName])
        #expect(names.count == 3)
        #expect(profile.reference.recordName.hasPrefix("profile-"))
        #expect(bookmark.reference.recordName.hasPrefix("bookmark-"))
        #expect(word.reference.recordName.hasPrefix("word-"))
    }

    @MainActor
    private func storeFixture(sync: any LibrarySyncing = DisabledLibrarySync()) throws -> StoreFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-sync-fixture-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "PiperlyTests.SyncFixture.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return StoreFixture(
            store: BookStore(
                documentsURL: root.appendingPathComponent("Books", isDirectory: true),
                coversURL: root.appendingPathComponent("Covers", isDirectory: true),
                userDefaults: defaults,
                librarySync: sync
            ),
            root: root,
            defaults: defaults,
            suiteName: suiteName
        )
    }
}

@MainActor
private struct StoreFixture {
    let store: BookStore
    let root: URL
    let defaults: UserDefaults
    let suiteName: String

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct FailingLibrarySync: LibrarySyncing {
    func enqueue(_ operations: [LibraryOutboxOperation]) throws {
        throw LibraryOutboxError.unavailable
    }

    func flush() throws {
        throw LibraryOutboxError.unavailable
    }
}
