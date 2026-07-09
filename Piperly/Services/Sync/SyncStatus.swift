// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import CloudKit
import Foundation

enum SyncAccountState: Sendable, Equatable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

enum SyncFailure: Sendable, Equatable {
    case retryable(retryAfter: Date?)
    case accountUnavailable
    case accountRestricted
    case quotaExceeded
    case permissionDenied
    case invalidSchema
    case missingLocalData
    case unknown(code: Int)
}

enum LibrarySyncStatus: Sendable, Equatable {
    case disabled
    case idle
    case syncing
    case waitingToRetry(Date?)
    case accountConfirmationRequired
    case blocked(SyncFailure)
}

enum BookAssetSyncStatusResolver {
    static func status(for failures: [String: BookAssetTransferFailure]) -> LibrarySyncStatus {
        if failures.values.contains(.blocked) { return .blocked(.quotaExceeded) }
        if failures.values.contains(where: { $0 == .missingLocalData || $0 == .corrupt }) {
            return .blocked(.missingLocalData)
        }
        if failures.values.contains(.retryable) { return .waitingToRetry(nil) }
        return .idle
    }
}

struct BookAssetRetryQueue: Sendable {
    private(set) var queued: Set<String> = []
    private(set) var isDraining = false

    mutating func enqueue(_ identity: String) -> Bool {
        queued.insert(identity)
        guard !isDraining else { return false }
        isDraining = true
        return true
    }

    mutating func takeNext() -> Set<String> {
        let next = queued
        queued.subtract(next)
        return next
    }

    mutating func finish() {
        isDraining = false
    }
}

enum AccountTransitionPolicy: Sendable, Equatable {
    case discardPendingChanges
    case keepLocalAndUploadAfterFetch
}

enum SyncAccountTransition {
    static func quarantine(snapshot: inout SyncStateSnapshot) {
        snapshot.quarantinedSaves.merge(snapshot.pendingSaves) { _, current in current }
        for deletion in snapshot.pendingDeletes {
            snapshot.quarantinedSaves[deletion.recordName] = nil
            snapshot.quarantinedDeletes.removeAll { $0 == deletion }
            snapshot.quarantinedDeletes.append(deletion)
        }
        snapshot.pendingSaves = [:]
        snapshot.pendingDeletes = []
    }

    static func resolve(policy: AccountTransitionPolicy, snapshot: inout SyncStateSnapshot) {
        switch policy {
        case .discardPendingChanges:
            snapshot.quarantinedSaves = [:]
            snapshot.quarantinedDeletes = []
        case .keepLocalAndUploadAfterFetch:
            snapshot.pendingSaves = snapshot.quarantinedSaves
            snapshot.pendingDeletes = snapshot.quarantinedDeletes
            snapshot.quarantinedSaves = [:]
            snapshot.quarantinedDeletes = []
        }
    }

    static func refreshQuarantinedSaves(
        from records: [LibraryRecord],
        snapshot: inout SyncStateSnapshot
    ) {
        let recordsByReference = Dictionary(uniqueKeysWithValues: records.map { ($0.reference, $0) })
        for (recordName, record) in snapshot.quarantinedSaves {
            if let refreshed = recordsByReference[record.reference] {
                snapshot.quarantinedSaves[recordName] = refreshed
            }
        }
    }
}

enum SyncInitialLibrarySeeder {
    static func seedIfNeeded(
        records: [LibraryRecord],
        policy: AccountTransitionPolicy,
        snapshot: inout SyncStateSnapshot
    ) {
        guard !snapshot.didSeedExistingLibrary else { return }
        if policy == .keepLocalAndUploadAfterFetch {
            for record in records where !snapshot.pendingDeletes.contains(record.reference) {
                snapshot.pendingSaves[record.reference.recordName] = record
            }
        }
        snapshot.didSeedExistingLibrary = true
    }
}

enum SyncCurrentAccountOperations {
    static func hasOperations(snapshot: SyncStateSnapshot) -> Bool {
        !snapshot.currentAccountSaves.isEmpty || !snapshot.currentAccountDeletes.isEmpty
    }

    static func recordSave(
        _ record: LibraryRecord,
        accountRecordName: String,
        transitionGeneration: Int,
        snapshot: inout SyncStateSnapshot
    ) {
        prepareBucket(
            accountRecordName: accountRecordName,
            transitionGeneration: transitionGeneration,
            snapshot: &snapshot
        )
        snapshot.currentAccountDeletes.removeAll { $0 == record.reference }
        snapshot.currentAccountSaves[record.reference.recordName] = record
    }

    static func recordDelete(
        _ reference: LibraryRecordReference,
        accountRecordName: String,
        transitionGeneration: Int,
        snapshot: inout SyncStateSnapshot
    ) {
        prepareBucket(
            accountRecordName: accountRecordName,
            transitionGeneration: transitionGeneration,
            snapshot: &snapshot
        )
        snapshot.currentAccountSaves[reference.recordName] = nil
        snapshot.currentAccountDeletes.removeAll { $0 == reference }
        snapshot.currentAccountDeletes.append(reference)
    }

    static func commitIfMatching(
        accountRecordName: String,
        transitionGeneration: Int,
        snapshot: inout SyncStateSnapshot
    ) -> Bool {
        guard hasOperations(snapshot: snapshot) else {
            clear(snapshot: &snapshot)
            return true
        }
        guard snapshot.currentAccountRecordName == accountRecordName,
              snapshot.currentAccountTransitionGeneration == transitionGeneration else {
            reQuarantine(snapshot: &snapshot)
            return false
        }
        for (recordName, record) in snapshot.currentAccountSaves {
            snapshot.pendingDeletes.removeAll { $0 == record.reference }
            snapshot.pendingSaves[recordName] = record
        }
        for deletion in snapshot.currentAccountDeletes {
            snapshot.pendingSaves[deletion.recordName] = nil
            snapshot.pendingDeletes.removeAll { $0 == deletion }
            snapshot.pendingDeletes.append(deletion)
        }
        clear(snapshot: &snapshot)
        return true
    }

    static func reQuarantine(snapshot: inout SyncStateSnapshot) {
        for (recordName, record) in snapshot.currentAccountSaves {
            snapshot.quarantinedDeletes.removeAll { $0 == record.reference }
            snapshot.quarantinedSaves[recordName] = record
        }
        for deletion in snapshot.currentAccountDeletes {
            snapshot.quarantinedSaves[deletion.recordName] = nil
            snapshot.quarantinedDeletes.removeAll { $0 == deletion }
            snapshot.quarantinedDeletes.append(deletion)
        }
        clear(snapshot: &snapshot)
    }

    private static func prepareBucket(
        accountRecordName: String,
        transitionGeneration: Int,
        snapshot: inout SyncStateSnapshot
    ) {
        if hasOperations(snapshot: snapshot)
            && (snapshot.currentAccountRecordName != accountRecordName
                || snapshot.currentAccountTransitionGeneration != transitionGeneration) {
            reQuarantine(snapshot: &snapshot)
        }
        snapshot.currentAccountRecordName = accountRecordName
        snapshot.currentAccountTransitionGeneration = transitionGeneration
    }

    private static func clear(snapshot: inout SyncStateSnapshot) {
        snapshot.currentAccountSaves = [:]
        snapshot.currentAccountDeletes = []
        snapshot.currentAccountRecordName = nil
        snapshot.currentAccountTransitionGeneration = nil
    }
}

enum CloudKitErrorClassifier {
    static func classify(_ error: CKError, now: Date = .now) -> SyncFailure {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .accountTemporarilyUnavailable,
             .operationCancelled:
            let retryAfter = error.retryAfterSeconds.map { now.addingTimeInterval($0) }
            return .retryable(retryAfter: retryAfter)
        case .notAuthenticated:
            return .accountUnavailable
        case .managedAccountRestricted:
            return .accountRestricted
        case .quotaExceeded:
            return .quotaExceeded
        case .permissionFailure:
            return .permissionDenied
        case .badContainer, .invalidArguments, .serverRejectedRequest:
            return .invalidSchema
        case .assetFileNotFound:
            return .missingLocalData
        default:
            return .unknown(code: error.code.rawValue)
        }
    }
}

enum CloudKitRetryPolicy {
    static func pendingSave(
        recordID: CKRecord.ID,
        error: CKError
    ) -> CKSyncEngine.PendingRecordZoneChange? {
        guard case .retryable = CloudKitErrorClassifier.classify(error) else { return nil }
        return .saveRecord(recordID)
    }
}

enum FetchedRecordReconciler {
    static func isTombstoned(
        _ reference: LibraryRecordReference,
        pendingDeletes: [LibraryRecordReference],
        quarantinedDeletes: [LibraryRecordReference]
    ) -> Bool {
        pendingDeletes.contains(reference) || quarantinedDeletes.contains(reference)
    }

    static func applyRemoteDeletion(
        _ reference: LibraryRecordReference,
        snapshot: inout SyncStateSnapshot
    ) {
        snapshot.pendingSaves[reference.recordName] = nil
        snapshot.pendingDeletes.removeAll { $0 == reference }
        snapshot.deferredRemoteRecords[reference.recordName] = nil
        snapshot.systemFields[reference.recordName] = nil
    }
}

// Bounded retention for the snapshot's deferred/quarantine buckets and delete
// tombstones. Without this, a child whose parent never arrives sits in the
// deferred bucket forever and a sent-then-cleared delete has no lasting record,
// so an older cross-device save can resurrect it.
enum SyncSnapshotMaintenance {
    static let maxBucketEntries = 512
    static let tombstoneLifetime: TimeInterval = 30 * 24 * 60 * 60 // 30 days

    // Records a delete so a later, older incoming save for the same record name
    // can be rejected. Bounded by count (drop-oldest) and age.
    static func recordTombstone(
        _ recordName: String,
        at date: Date,
        snapshot: inout SyncStateSnapshot
    ) {
        snapshot.tombstones[recordName] = date
        pruneTombstones(now: date, snapshot: &snapshot)
    }

    // True when a save for this record name is older than a live tombstone, i.e.
    // it predates a delete we already applied and must not be resurrected.
    static func isBlockedByTombstone(
        _ recordName: String,
        incomingModifiedAt: Date,
        now: Date,
        snapshot: SyncStateSnapshot
    ) -> Bool {
        guard let deletedAt = snapshot.tombstones[recordName] else { return false }
        guard now.timeIntervalSince(deletedAt) < tombstoneLifetime else { return false }
        return incomingModifiedAt <= deletedAt
    }

    static func prune(now: Date, snapshot: inout SyncStateSnapshot) {
        pruneTombstones(now: now, snapshot: &snapshot)
        capOldest(&snapshot.deferredRemoteRecords)
        capOldest(&snapshot.quarantinedSaves)
        capOldest(&snapshot.accountTransitionRemoteRecords)
    }

    private static func pruneTombstones(now: Date, snapshot: inout SyncStateSnapshot) {
        snapshot.tombstones = snapshot.tombstones.filter {
            now.timeIntervalSince($0.value) < tombstoneLifetime
        }
        if snapshot.tombstones.count > maxBucketEntries {
            let keep = snapshot.tombstones.sorted { $0.value > $1.value }.prefix(maxBucketEntries)
            snapshot.tombstones = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    // Keeps the newest-by-record entries; ties broken by record name for
    // determinism (no wall clock available in this pure layer).
    private static func capOldest(_ bucket: inout [String: LibraryRecord]) {
        guard bucket.count > maxBucketEntries else { return }
        let keep = bucket.sorted {
            let lhs = $0.value.modifiedAt, rhs = $1.value.modifiedAt
            return lhs == rhs ? $0.key > $1.key : lhs > rhs
        }.prefix(maxBucketEntries)
        bucket = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
}

private extension LibraryRecord {
    var modifiedAt: Date {
        switch self {
        case .book(let value): value.modifiedAt
        case .readerProfile(let value): value.modifiedAt
        case .readerPreferences(let value): value.modifiedAt
        case .readingState(let value): value.modifiedAt
        case .bookmark(let value): value.modifiedAt
        case .savedWord(let value): value.modifiedAt
        }
    }
}

enum SyncAccountTransitionValidator {
    static func validate(initialRecordName: String, verifiedRecordName: String) throws {
        guard initialRecordName == verifiedRecordName else {
            throw SyncAccountTransitionError.accountChangedDuringConfirmation
        }
    }

    static func validateGeneration(
        expected: Int,
        current: Int,
        isTransitionActive: Bool
    ) throws {
        guard isTransitionActive, expected == current else {
            throw SyncAccountTransitionError.accountChangedDuringConfirmation
        }
    }
}

enum AccountTransitionRemoteReconciler {
    static func changes(
        records: [LibraryRecord],
        deletions: [LibraryRecordReference],
        policy: AccountTransitionPolicy,
        initialLocalRecords: [LibraryRecord],
        quarantinedSaves: [LibraryRecord],
        quarantinedDeletes: [LibraryRecordReference]
    ) -> [LibraryRemoteChange] {
        var records = records
        var deletions = deletions
        if policy == .keepLocalAndUploadAfterFetch {
            let protectedReferences = Set(
                initialLocalRecords.map(\.reference) + quarantinedSaves.map(\.reference)
            )
            let localDeletions = Set(quarantinedDeletes)
            deletions.removeAll { protectedReferences.contains($0) }
            records.removeAll { localDeletions.contains($0.reference) }
        }
        return deletions.map(LibraryRemoteChange.delete)
            + records.map(LibraryRemoteChange.save)
    }

    static func assetChanges(
        for changes: [LibraryRemoteChange],
        stagedAssets: [String: BookAssetURLs]
    ) -> [LibraryRemoteChange] {
        let savedBookNames = Set(changes.compactMap { change -> String? in
            guard case .save(let record) = change, case .book = record else { return nil }
            return record.reference.recordName
        })
        return stagedAssets.compactMap { identity, files in
            guard savedBookNames.contains(identity) else { return nil }
            return .bookAssets(contentIdentity: identity, files: files)
        }
    }
}
