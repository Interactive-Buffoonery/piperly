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
}
