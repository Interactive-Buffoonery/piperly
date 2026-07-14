// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import CloudKit
import Foundation
import UIKit

actor CloudKitLibrarySync: LibrarySyncSink {
    typealias RemoteChangeHandler = @MainActor @Sendable (
        [LibraryRemoteChange],
        RemoteApplicationScope
    ) -> RemoteApplicationResult
    typealias LocalSnapshotProvider = @MainActor @Sendable () -> [LibraryRecord]

    static let containerIdentifier = "iCloud.com.piperly.app"
    static let enabledDefaultsKey = "piperly_icloud_sync_enabled"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledDefaultsKey)
    }

    private let container: CKContainer
    private let stateStore: SyncStateStore
    private let remoteChangeHandler: RemoteChangeHandler
    private let localSnapshotProvider: LocalSnapshotProvider
    private let automaticallySync: Bool
    private var snapshot: SyncStateSnapshot
    private var engine: CKSyncEngine?
    private var needsAccountConfirmation = false
    private var accountTransitionInProgress = false
    private(set) var status: LibrarySyncStatus

    init(
        enabled: Bool,
        container: CKContainer = CKContainer(identifier: CloudKitLibrarySync.containerIdentifier),
        stateURL: URL = CloudKitLibrarySync.defaultStateURL,
        automaticallySync: Bool = true,
        localSnapshotProvider: @escaping LocalSnapshotProvider = { [] },
        remoteChangeHandler: @escaping RemoteChangeHandler
    ) throws {
        self.container = container
        stateStore = SyncStateStore(fileURL: stateURL)
        self.remoteChangeHandler = remoteChangeHandler
        self.localSnapshotProvider = localSnapshotProvider
        self.automaticallySync = automaticallySync
        snapshot = try stateStore.load()
        status = enabled ? .idle : .disabled
        needsAccountConfirmation = enabled

        if enabled {
            Task { await self.prepareInitialAccount() }
        }
    }

    static var defaultStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Piperly", isDirectory: true)
            .appendingPathComponent("CloudKitSync.json")
    }

    private func prepareInitialAccount() async {
        guard let currentUser = try? await container.userRecordID() else {
            status = .blocked(.accountUnavailable)
            return
        }
        if SyncCurrentAccountOperations.hasOperations(snapshot: snapshot) {
            SyncCurrentAccountOperations.reQuarantine(snapshot: &snapshot)
            snapshot.confirmedAccountRecordName = nil
        }
        guard snapshot.confirmedAccountRecordName == currentUser.recordName else {
            SyncAccountTransition.quarantine(snapshot: &snapshot)
            needsAccountConfirmation = true
            status = .accountConfirmationRequired
            persistSnapshot()
            return
        }
        SyncAccountTransition.resolve(policy: .keepLocalAndUploadAfterFetch, snapshot: &snapshot)
        needsAccountConfirmation = false
        persistSnapshot()
        start()
    }

    func start(automaticallySync override: Bool? = nil, restorePending: Bool = true) {
        guard status != .disabled, engine == nil, !needsAccountConfirmation else { return }
        Task { @MainActor in
            UIApplication.shared.registerForRemoteNotifications()
        }
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: snapshot.engineState,
            delegate: self
        )
        configuration.automaticallySync = override ?? automaticallySync
        configuration.subscriptionID = "PiperlyLibrary-private"
        let newEngine = CKSyncEngine(configuration)
        engine = newEngine
        if restorePending { restorePendingChanges(to: newEngine) }
    }

    func acceptSave(_ record: LibraryRecord, scope: RemoteApplicationScope) async throws {
        let reference = record.reference
        if scope.isCurrentAccount {
            guard let accountRecordName = scope.accountRecordName,
                  let transitionGeneration = scope.transitionGeneration else { return }
            if matchesActiveTransition(scope) {
                SyncCurrentAccountOperations.recordSave(
                    record,
                    accountRecordName: accountRecordName,
                    transitionGeneration: transitionGeneration,
                    snapshot: &snapshot
                )
            } else if matchesConfirmedTransition(scope) {
                snapshot.pendingDeletes.removeAll { $0 == reference }
                snapshot.pendingSaves[reference.recordName] = record
            } else {
                quarantineSave(record)
                requireNewAccountConfirmation()
            }
            try persistSnapshotOrThrow()
            return
        }
        if needsAccountConfirmation || accountTransitionInProgress {
            snapshot.quarantinedDeletes.removeAll { $0 == reference }
            snapshot.quarantinedSaves[reference.recordName] = record
            try persistSnapshotOrThrow()
            return
        }
        snapshot.pendingDeletes.removeAll { $0 == reference }
        snapshot.pendingSaves[reference.recordName] = record
        try persistSnapshotOrThrow()
        guard let engine = activeEngine() else { return }
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(for: reference))])
    }

    func acceptDelete(
        _ reference: LibraryRecordReference,
        scope: RemoteApplicationScope
    ) async throws {
        if scope.isCurrentAccount {
            guard let accountRecordName = scope.accountRecordName,
                  let transitionGeneration = scope.transitionGeneration else { return }
            if matchesActiveTransition(scope) {
                SyncCurrentAccountOperations.recordDelete(
                    reference,
                    accountRecordName: accountRecordName,
                    transitionGeneration: transitionGeneration,
                    snapshot: &snapshot
                )
            } else if matchesConfirmedTransition(scope) {
                snapshot.pendingSaves[reference.recordName] = nil
                snapshot.pendingDeletes.removeAll { $0 == reference }
                snapshot.pendingDeletes.append(reference)
            } else {
                quarantineDelete(reference)
                requireNewAccountConfirmation()
            }
            try persistSnapshotOrThrow()
            return
        }
        if needsAccountConfirmation || accountTransitionInProgress {
            snapshot.quarantinedSaves[reference.recordName] = nil
            snapshot.quarantinedDeletes.removeAll { $0 == reference }
            snapshot.quarantinedDeletes.append(reference)
            try persistSnapshotOrThrow()
            return
        }
        snapshot.pendingSaves[reference.recordName] = nil
        snapshot.pendingDeletes.removeAll { $0 == reference }
        snapshot.pendingDeletes.append(reference)
        try persistSnapshotOrThrow()
        guard let engine = activeEngine() else { return }
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(for: reference))])
    }

    func syncNow() async throws {
        guard let engine = activeEngine() else { return }
        try await engine.fetchChanges(CKSyncEngine.FetchChangesOptions())
        try await engine.sendChanges(CKSyncEngine.SendChangesOptions())
    }

    func accountState() async -> SyncAccountState {
        guard status != .disabled else { return .couldNotDetermine }
        do {
            switch try await container.accountStatus() {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            case .couldNotDetermine:
                return .couldNotDetermine
            @unknown default:
                return .couldNotDetermine
            }
        } catch {
            return .couldNotDetermine
        }
    }

    func confirmAccountChange(policy: AccountTransitionPolicy) async throws {
        guard needsAccountConfirmation else { return }
        do {
            let generation = beginAccountTransition()
            let currentUser = try await container.userRecordID()
            try requireAccountTransition(generation)
            snapshot.accountTransitionAccountRecordName = currentUser.recordName
            let initialLocalRecords = await localSnapshotProvider()
            try requireAccountTransition(generation)
            try persistSnapshotOrThrow()
            start(automaticallySync: false, restorePending: false)
            guard let fetchEngine = engine else {
                throw SyncAccountTransitionError.accountChangedDuringConfirmation
            }
            try await fetchEngine.fetchChanges(CKSyncEngine.FetchChangesOptions())
            try requireAccountTransition(generation)
            await fetchEngine.cancelOperations()
            try requireAccountTransition(generation)
            engine = nil
            let firstVerification = try await container.userRecordID()
            try requireAccountTransition(generation)
            try SyncAccountTransitionValidator.validate(
                initialRecordName: currentUser.recordName,
                verifiedRecordName: firstVerification.recordName
            )
            let applicationResult = await applyStagedAccountChanges(
                policy: policy,
                initialLocalRecords: initialLocalRecords,
                accountRecordName: currentUser.recordName,
                transitionGeneration: generation
            )
            try requireAccountTransition(generation)
            let postMergeLocalRecords = await localSnapshotProvider()
            try requireAccountTransition(generation)
            let finalVerification = try await container.userRecordID()
            try requireAccountTransition(generation)
            try SyncAccountTransitionValidator.validate(
                initialRecordName: currentUser.recordName,
                verifiedRecordName: finalVerification.recordName
            )
            snapshot.deferredRemoteRecords = Dictionary(
                uniqueKeysWithValues: applicationResult.unresolvedRecords.map {
                    ($0.reference.recordName, $0)
                }
            )
            snapshot.deferredRemoteDeletions = applicationResult.unresolvedDeletions
            snapshot.accountTransitionRemoteRecords = [:]
            snapshot.accountTransitionRemoteDeletions = []
            SyncAccountTransition.refreshQuarantinedSaves(
                from: postMergeLocalRecords,
                snapshot: &snapshot
            )
            SyncAccountTransition.resolve(policy: policy, snapshot: &snapshot)
            guard SyncCurrentAccountOperations.commitIfMatching(
                accountRecordName: finalVerification.recordName,
                transitionGeneration: generation,
                snapshot: &snapshot
            ) else {
                throw SyncAccountTransitionError.accountChangedDuringConfirmation
            }
            SyncInitialLibrarySeeder.seedIfNeeded(
                records: postMergeLocalRecords,
                policy: policy,
                snapshot: &snapshot
            )
            snapshot.confirmedAccountRecordName = finalVerification.recordName
            snapshot.accountTransitionAccountRecordName = nil
            try requireAccountTransition(generation)
            accountTransitionInProgress = false
            needsAccountConfirmation = false
            status = .idle
            try persistSnapshotOrThrow()
            start()
        } catch {
            failAccountTransitionIfActive()
            throw error
        }
    }

    private func matchesActiveTransition(_ scope: RemoteApplicationScope) -> Bool {
        accountTransitionInProgress
            && scope.accountRecordName == snapshot.accountTransitionAccountRecordName
            && scope.transitionGeneration == snapshot.accountTransitionGeneration
    }

    private func matchesConfirmedTransition(_ scope: RemoteApplicationScope) -> Bool {
        !accountTransitionInProgress
            && !needsAccountConfirmation
            && scope.accountRecordName == snapshot.confirmedAccountRecordName
            && scope.transitionGeneration == snapshot.accountTransitionGeneration
    }

    private func quarantineSave(_ record: LibraryRecord) {
        snapshot.quarantinedDeletes.removeAll { $0 == record.reference }
        snapshot.quarantinedSaves[record.reference.recordName] = record
    }

    private func quarantineDelete(_ reference: LibraryRecordReference) {
        snapshot.quarantinedSaves[reference.recordName] = nil
        snapshot.quarantinedDeletes.removeAll { $0 == reference }
        snapshot.quarantinedDeletes.append(reference)
    }

    private func requireNewAccountConfirmation() {
        if accountTransitionInProgress {
            invalidateAccountTransition()
            return
        }
        if let engine { Task { await engine.cancelOperations() } }
        engine = nil
        SyncAccountTransition.quarantine(snapshot: &snapshot)
        snapshot.confirmedAccountRecordName = nil
        needsAccountConfirmation = true
        status = .accountConfirmationRequired
    }

    private func activeEngine() -> CKSyncEngine? {
        guard status != .disabled, !needsAccountConfirmation, !accountTransitionInProgress else { return nil }
        if engine == nil { start() }
        return engine
    }

    private func restorePendingChanges(to engine: CKSyncEngine) {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: LibraryRecordCodec.zoneID))])
        let saves = snapshot.pendingSaves.values.map { record in
            CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID(for: record.reference))
        }
        let deletes = snapshot.pendingDeletes.map { reference in
            CKSyncEngine.PendingRecordZoneChange.deleteRecord(recordID(for: reference))
        }
        engine.state.add(pendingRecordZoneChanges: saves + deletes)
    }

    private func recordID(for reference: LibraryRecordReference) -> CKRecord.ID {
        CKRecord.ID(recordName: reference.recordName, zoneID: LibraryRecordCodec.zoneID)
    }

    private func persistSnapshot() {
        SyncSnapshotMaintenance.prune(now: .now, snapshot: &snapshot)
        do {
            try stateStore.save(snapshot)
        } catch {
            status = .blocked(.missingLocalData)
        }
    }

    private func persistSnapshotOrThrow() throws {
        SyncSnapshotMaintenance.prune(now: .now, snapshot: &snapshot)
        do {
            try stateStore.save(snapshot)
        } catch {
            status = .blocked(.missingLocalData)
            throw error
        }
    }
}

extension CloudKitLibrarySync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            snapshot.engineState = update.stateSerialization
            persistSnapshot()
        case .accountChange where accountTransitionInProgress:
            abortAccountTransition(syncEngine: syncEngine)
        case .accountChange(let change) where accountRequiresConfirmation(change):
            abortAccountTransition(syncEngine: syncEngine)
        case .accountChange:
            break
        case .fetchedRecordZoneChanges(let changes):
            await handleFetched(changes)
        case .sentRecordZoneChanges(let changes):
            handleSent(changes, syncEngine: syncEngine)
        case .sentDatabaseChanges(let changes):
            handleSentDatabaseChanges(changes, syncEngine: syncEngine)
        case .willFetchChanges, .willSendChanges:
            status = .syncing
        case .didFetchChanges, .didSendChanges:
            if !needsAccountConfirmation { status = .idle }
        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == LibraryRecordCodec.zoneID }) {
                syncEngine.state.add(pendingDatabaseChanges: [
                    .saveZone(CKRecordZone(zoneID: LibraryRecordCodec.zoneID)),
                ])
            }
        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !needsAccountConfirmation, !accountTransitionInProgress else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let records = snapshot.pendingSaves
        let systemFields = snapshot.systemFields
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            guard let record = records[recordID.recordName] else { return nil }
            return try? LibraryRecordCodec.encode(record, systemFields: systemFields[recordID.recordName])
        }
    }

    private func handleFetched(_ event: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        guard !needsAccountConfirmation else { return }
        if accountTransitionInProgress {
            stageFetchedForAccountTransition(event)
            persistSnapshot()
            return
        }
        var records = snapshot.deferredRemoteRecords
        var deletionReferences = snapshot.deferredRemoteDeletions
        for modification in event.modifications where modification.record.recordID.zoneID == LibraryRecordCodec.zoneID {
            let record = modification.record
            guard let decoded = try? LibraryRecordCodec.decode(record) else { continue }
            let reference = decoded.reference
            let hasTombstone = FetchedRecordReconciler.isTombstoned(
                reference,
                pendingDeletes: snapshot.pendingDeletes,
                quarantinedDeletes: snapshot.quarantinedDeletes
            )
            if hasTombstone {
                records[reference.recordName] = nil
                engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(record.recordID)])
                continue
            }
            if SyncSnapshotMaintenance.isBlockedByTombstone(
                reference.recordName,
                incomingModifiedAt: modification.record.modificationDate ?? .distantPast,
                now: .now,
                snapshot: snapshot
            ) {
                records[reference.recordName] = nil
                continue
            }
            let value: LibraryRecord
            if let pending = snapshot.pendingSaves[record.recordID.recordName] {
                value = LibraryConflictResolver.merge(local: pending, remote: decoded)
                snapshot.pendingSaves[record.recordID.recordName] = value
            } else {
                value = decoded
            }
            snapshot.systemFields[record.recordID.recordName] = LibraryRecordCodec.systemFieldsData(for: record)
            records[reference.recordName] = value
        }
        for deletion in event.deletions where deletion.recordID.zoneID == LibraryRecordCodec.zoneID {
            let reference = LibraryRecordReference(
                recordType: deletion.recordType,
                recordName: deletion.recordID.recordName
            )
            FetchedRecordReconciler.applyRemoteDeletion(reference, snapshot: &snapshot)
            SyncSnapshotMaintenance.recordTombstone(reference.recordName, at: .now, snapshot: &snapshot)
            records[reference.recordName] = nil
            deletionReferences.removeAll { $0 == reference }
            deletionReferences.append(reference)
        }
        let saves = records.values.map(LibraryRemoteChange.save)
        let changes = deletionReferences.map(LibraryRemoteChange.delete) + saves
        if changes.isEmpty {
            snapshot.deferredRemoteRecords = records
        } else {
            let result = await remoteChangeHandler(changes, .normal)
            snapshot.deferredRemoteRecords = Dictionary(
                uniqueKeysWithValues: result.unresolvedRecords.map { ($0.reference.recordName, $0) }
            )
            snapshot.deferredRemoteDeletions = result.unresolvedDeletions
        }
        persistSnapshot()
    }

    private func stageFetchedForAccountTransition(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges
    ) {
        for modification in event.modifications where modification.record.recordID.zoneID == LibraryRecordCodec.zoneID {
            let record = modification.record
            guard let decoded = try? LibraryRecordCodec.decode(record) else { continue }
            snapshot.accountTransitionRemoteDeletions.removeAll { $0 == decoded.reference }
            snapshot.accountTransitionRemoteRecords[decoded.reference.recordName] = decoded
            snapshot.systemFields[record.recordID.recordName] = LibraryRecordCodec.systemFieldsData(for: record)
        }
        for deletion in event.deletions where deletion.recordID.zoneID == LibraryRecordCodec.zoneID {
            let reference = LibraryRecordReference(
                recordType: deletion.recordType,
                recordName: deletion.recordID.recordName
            )
            snapshot.accountTransitionRemoteRecords[reference.recordName] = nil
            snapshot.accountTransitionRemoteDeletions.removeAll { $0 == reference }
            snapshot.accountTransitionRemoteDeletions.append(reference)
            snapshot.systemFields[reference.recordName] = nil
        }
    }

    private func handleSent(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) {
        for record in event.savedRecords {
            snapshot.systemFields[record.recordID.recordName] = LibraryRecordCodec.systemFieldsData(for: record)
            if let pending = snapshot.pendingSaves[record.recordID.recordName],
               let sent = try? LibraryRecordCodec.decode(record), pending == sent {
                snapshot.pendingSaves[record.recordID.recordName] = nil
            } else if let pending = snapshot.pendingSaves[record.recordID.recordName] {
                syncEngine.state.add(pendingRecordZoneChanges: [
                    .saveRecord(recordID(for: pending.reference)),
                ])
            }
        }
        for recordID in event.deletedRecordIDs {
            snapshot.pendingDeletes.removeAll { $0.recordName == recordID.recordName }
            SyncSnapshotMaintenance.recordTombstone(recordID.recordName, at: .now, snapshot: &snapshot)
            snapshot.systemFields[recordID.recordName] = nil
            if let pending = snapshot.pendingSaves[recordID.recordName] {
                syncEngine.state.add(pendingRecordZoneChanges: [
                    .saveRecord(self.recordID(for: pending.reference)),
                ])
            }
        }
        for failure in event.failedRecordSaves {
            handleSaveFailure(failure, syncEngine: syncEngine)
        }
        for (recordID, error) in event.failedRecordDeletes {
            apply(error: error)
            if case .retryable = CloudKitErrorClassifier.classify(error) {
                syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            }
        }
        persistSnapshot()
    }

    private func handleSaveFailure(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        syncEngine: CKSyncEngine
    ) {
        let recordID = failure.record.recordID
        if failure.error.code == .serverRecordChanged,
           let serverRecord = failure.error.serverRecord,
           let remote = try? LibraryRecordCodec.decode(serverRecord),
           let local = snapshot.pendingSaves[recordID.recordName] {
            snapshot.pendingSaves[recordID.recordName] = LibraryConflictResolver.merge(local: local, remote: remote)
            snapshot.systemFields[recordID.recordName] = LibraryRecordCodec.systemFieldsData(for: serverRecord)
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return
        }
        if failure.error.code == .zoneNotFound {
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: LibraryRecordCodec.zoneID))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return
        }
        apply(error: failure.error)
        if let pending = CloudKitRetryPolicy.pendingSave(recordID: recordID, error: failure.error) {
            syncEngine.state.add(pendingRecordZoneChanges: [pending])
        }
    }

    private func handleSentDatabaseChanges(
        _ event: CKSyncEngine.Event.SentDatabaseChanges,
        syncEngine: CKSyncEngine
    ) {
        for failure in event.failedZoneSaves {
            apply(error: failure.error)
            if case .retryable = CloudKitErrorClassifier.classify(failure.error) {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(failure.zone)])
            }
        }
    }

    private func apply(error: CKError) {
        let failure = CloudKitErrorClassifier.classify(error)
        if case .retryable(let retryAfter) = failure {
            status = .waitingToRetry(retryAfter)
        } else {
            status = .blocked(failure)
        }
    }

    private func accountRequiresConfirmation(_ change: CKSyncEngine.Event.AccountChange) -> Bool {
        switch change.changeType {
        case .signIn(let currentUser):
            currentUser.recordName != snapshot.confirmedAccountRecordName
        case .signOut, .switchAccounts:
            true
        @unknown default:
            true
        }
    }

    private func beginAccountTransition() -> Int {
        SyncCurrentAccountOperations.reQuarantine(snapshot: &snapshot)
        snapshot.accountTransitionGeneration += 1
        engine = nil
        snapshot.engineState = nil
        snapshot.systemFields = [:]
        snapshot.accountTransitionRemoteRecords = [:]
        snapshot.accountTransitionRemoteDeletions = []
        snapshot.accountTransitionAccountRecordName = nil
        needsAccountConfirmation = false
        accountTransitionInProgress = true
        status = .syncing
        return snapshot.accountTransitionGeneration
    }

    private func requireAccountTransition(_ generation: Int) throws {
        try SyncAccountTransitionValidator.validateGeneration(
            expected: generation,
            current: snapshot.accountTransitionGeneration,
            isTransitionActive: accountTransitionInProgress
        )
    }

    private func applyStagedAccountChanges(
        policy: AccountTransitionPolicy,
        initialLocalRecords: [LibraryRecord],
        accountRecordName: String,
        transitionGeneration: Int
    ) async -> RemoteApplicationResult {
        let changes = AccountTransitionRemoteReconciler.changes(
            records: Array(snapshot.accountTransitionRemoteRecords.values),
            deletions: snapshot.accountTransitionRemoteDeletions,
            policy: policy,
            initialLocalRecords: initialLocalRecords,
            quarantinedSaves: Array(snapshot.quarantinedSaves.values),
            quarantinedDeletes: snapshot.quarantinedDeletes
        )
        guard !changes.isEmpty else { return .complete }
        return await remoteChangeHandler(
            changes,
            .currentAccount(
                accountRecordName: accountRecordName,
                transitionGeneration: transitionGeneration
            )
        )
    }

    private func failAccountTransitionIfActive() {
        guard accountTransitionInProgress else { return }
        if let engine { Task { await engine.cancelOperations() } }
        invalidateAccountTransition()
        persistSnapshot()
    }

    private func invalidateAccountTransition() {
        SyncCurrentAccountOperations.reQuarantine(snapshot: &snapshot)
        snapshot.accountTransitionGeneration += 1
        engine = nil
        snapshot.engineState = nil
        snapshot.systemFields = [:]
        snapshot.confirmedAccountRecordName = nil
        snapshot.accountTransitionRemoteRecords = [:]
        snapshot.accountTransitionRemoteDeletions = []
        snapshot.accountTransitionAccountRecordName = nil
        SyncAccountTransition.quarantine(snapshot: &snapshot)
        needsAccountConfirmation = true
        accountTransitionInProgress = false
        status = .accountConfirmationRequired
    }

    private func abortAccountTransition(syncEngine: CKSyncEngine) {
        invalidateAccountTransition()
        persistSnapshot()
        Task { await syncEngine.cancelOperations() }
    }
}

enum SyncAccountTransitionError: Error, Equatable {
    case accountChangedDuringConfirmation
}
