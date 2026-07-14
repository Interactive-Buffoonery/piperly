// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import CloudKit
import Foundation
import UIKit

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
actor CloudKitLibrarySync: LibrarySyncSink {
    typealias RemoteChangeHandler = @MainActor @Sendable (
        [LibraryRemoteChange],
        RemoteApplicationScope
    ) -> RemoteApplicationResult
    typealias LocalSnapshotProvider = @MainActor @Sendable () -> [LibraryRecord]
    typealias LocalBookAssetProvider = @MainActor @Sendable (SyncedBook) -> BookAssetURLs?
    typealias StatusHandler = @MainActor @Sendable (LibrarySyncStatus) -> Void

    static let containerIdentifier = "iCloud.com.piperly.app"
    static let enabledDefaultsKey = "piperly_icloud_sync_enabled"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledDefaultsKey)
    }

    private let container: CKContainer
    private let stateStore: SyncStateStore
    private let remoteChangeHandler: RemoteChangeHandler
    private let localSnapshotProvider: LocalSnapshotProvider
    private let localBookAssetProvider: LocalBookAssetProvider
    private let assetStaging: BookAssetStaging
    private let automaticallySync: Bool
    private let statusHandler: StatusHandler
    private let activityToken = CloudSyncActivityToken()
    private var snapshot: SyncStateSnapshot
    private var engine: CKSyncEngine?
    private var engineActivityToken: CloudSyncActivityToken?
    private var needsAccountConfirmation = false
    private var accountTransitionInProgress = false
    private var transitionAssetApplicationInProgress = false
    private var activeUploadAssets: [String: [String: BookAssetURLs]] = [:]
    private var assetRetryQueue = BookAssetRetryQueue()
    private var isStopped = false
    private var lifecycleGeneration = 0
    private(set) var status: LibrarySyncStatus {
        didSet {
            guard !isStopped, status != oldValue else { return }
            let status = status
            let activityToken = activityToken
            Task { @MainActor [statusHandler] in
                guard activityToken.isActive else { return }
                statusHandler(status)
            }
        }
    }

    init(
        enabled: Bool,
        container: CKContainer = CKContainer(identifier: CloudKitLibrarySync.containerIdentifier),
        stateURL: URL = CloudKitLibrarySync.defaultStateURL,
        automaticallySync: Bool = true,
        localSnapshotProvider: @escaping LocalSnapshotProvider = { [] },
        localBookAssetProvider: @escaping LocalBookAssetProvider = { _ in nil },
        assetStagingURL: URL? = nil,
        statusHandler: @escaping StatusHandler = { _ in },
        remoteChangeHandler: @escaping RemoteChangeHandler
    ) throws {
        self.container = container
        stateStore = SyncStateStore(fileURL: stateURL)
        snapshot = try stateStore.load()
        self.remoteChangeHandler = remoteChangeHandler
        self.localSnapshotProvider = localSnapshotProvider
        self.localBookAssetProvider = localBookAssetProvider
        assetStaging = BookAssetStaging(
            rootURL: assetStagingURL ?? stateURL.deletingLastPathComponent()
                .appendingPathComponent("AssetStaging", isDirectory: true)
        )
        assetStaging.clearStaleFiles(retaining: Set(
            snapshot.pendingRemoteAssets.values.flatMap {
                [$0.files.epub, $0.files.cover].compactMap { $0 }
            }
                + snapshot.accountTransitionRemoteAssets.values.flatMap {
                    [$0.files.epub, $0.files.cover].compactMap { $0 }
                }
        ))
        self.automaticallySync = automaticallySync
        self.statusHandler = statusHandler
        status = enabled ? BookAssetSyncStatusResolver.status(for: snapshot.bookAssetFailures) : .disabled
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
        let generation = lifecycleGeneration
        guard isActive(generation) else { return }
        guard let currentUser = try? await container.userRecordID() else {
            guard isActive(generation) else { return }
            status = .blocked(.accountUnavailable)
            return
        }
        guard isActive(generation) else { return }
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
        await applyDeferredRemoteChanges()
        guard isActive(generation) else { return }
        start()
        await resumeDurableAssetRetries()
    }

    func start(automaticallySync override: Bool? = nil, restorePending: Bool = true) {
        guard !isStopped, status != .disabled, engine == nil, !needsAccountConfirmation else { return }
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
        engineActivityToken?.invalidate()
        engineActivityToken = CloudSyncActivityToken()
        engine = newEngine
        if restorePending { restorePendingChanges(to: newEngine) }
    }

    func acceptSave(_ record: LibraryRecord, scope: RemoteApplicationScope) async throws {
        guard !isStopped else { throw SyncLifecycleError.stopped }
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
        guard !isStopped else { throw SyncLifecycleError.stopped }
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
        let generation = lifecycleGeneration
        guard isActive(generation) else { throw SyncLifecycleError.stopped }
        guard let engine = activeEngine() else { return }
        try await engine.fetchChanges(CKSyncEngine.FetchChangesOptions())
        guard isActive(generation), engine === self.engine else { throw SyncLifecycleError.stopped }
        try await engine.sendChanges(CKSyncEngine.SendChangesOptions())
        guard isActive(generation), engine === self.engine else { throw SyncLifecycleError.stopped }
    }

    func stop() async {
        guard !isStopped else { return }
        isStopped = true
        activityToken.invalidate()
        lifecycleGeneration += 1
        let engineToStop = detachEngine()
        status = .disabled
        if let engineToStop { await engineToStop.cancelOperations() }
        cleanupActiveUploads()
    }

    func currentStatus() -> LibrarySyncStatus {
        status
    }

    func accountConfirmationContext() -> SyncAccountConfirmationContext {
        let hasPendingWork = !snapshot.quarantinedSaves.isEmpty
            || !snapshot.quarantinedDeletes.isEmpty
            || SyncCurrentAccountOperations.hasOperations(snapshot: snapshot)
        if snapshot.didSeedExistingLibrary || snapshot.confirmedAccountRecordName != nil {
            return hasPendingWork ? .accountChangedWithPendingWork : .accountChanged
        }
        return .firstEnable
    }

    func failedAssetIdentities() -> Set<String> {
        Set(snapshot.bookAssetFailures.keys).union(snapshot.assetDownloadRetryRecordNames)
    }

    func requestBookAssets(contentIdentity: String) async {
        guard !isStopped else { return }
        snapshot.recordAssetFailure(
            .retryable,
            recordName: contentIdentity,
            requiresDownloadRetry: true
        )
        persistSnapshot()
        guard assetRetryQueue.enqueue(contentIdentity) else { return }
        await drainAssetRetryQueue()
    }

    private func drainAssetRetryQueue() async {
        defer { assetRetryQueue.finish() }
        while !assetRetryQueue.queued.isEmpty {
            guard !isStopped, !needsAccountConfirmation, !accountTransitionInProgress else { return }
            let requested = assetRetryQueue.takeNext()
            await performAssetRetry(for: requested)
        }
    }

    private func resumeDurableAssetRetries() async {
        var ownsDrain = false
        for identity in snapshot.assetDownloadRetryRecordNames {
            ownsDrain = assetRetryQueue.enqueue(identity) || ownsDrain
        }
        if ownsDrain { await drainAssetRetryQueue() }
    }

    private func performAssetRetry(for identities: Set<String>) async {
        let lifecycle = lifecycleGeneration
        guard !identities.isEmpty,
              isActive(lifecycle),
              !needsAccountConfirmation,
              !accountTransitionInProgress,
              let expectedAccount = snapshot.confirmedAccountRecordName else { return }
        let expectedGeneration = snapshot.accountTransitionGeneration
        let previousEngine = detachEngine()
        if let previousEngine { await previousEngine.cancelOperations() }
        guard isActive(lifecycle),
              !needsAccountConfirmation,
              !accountTransitionInProgress,
              snapshot.confirmedAccountRecordName == expectedAccount,
              snapshot.accountTransitionGeneration == expectedGeneration else { return }
        cleanupActiveUploads()
        snapshot.engineState = nil
        persistSnapshot()
        start()
        guard let retryEngine = engine else { return }
        do {
            try await retryEngine.fetchChanges(CKSyncEngine.FetchChangesOptions())
            guard isActive(lifecycle), retryEngine === engine else { return }
        } catch {
            recordRetryError(error, identities: identities)
            return
        }
        guard retryAccountMatches(expectedAccount, generation: expectedGeneration) else {
            let staleEngine = detachEngine()
            if let staleEngine { await staleEngine.cancelOperations() }
            cleanupActiveUploads()
            return
        }
        do {
            try await retryEngine.sendChanges(CKSyncEngine.SendChangesOptions())
            guard isActive(lifecycle), retryEngine === engine else { return }
        } catch {
            recordRetryError(error, identities: identities)
            return
        }
        guard retryAccountMatches(expectedAccount, generation: expectedGeneration) else {
            let staleEngine = detachEngine()
            if let staleEngine { await staleEngine.cancelOperations() }
            cleanupActiveUploads()
            return
        }
    }

    private func recordRetryError(_ error: Error, identities: Set<String>) {
        let transferFailure: BookAssetTransferFailure
        let requiresDownloadRetry: Bool
        if let cloudError = error as? CKError,
           case .retryable(let retryAfter) = CloudKitErrorClassifier.classify(cloudError) {
            transferFailure = .retryable
            requiresDownloadRetry = true
            apply(error: cloudError)
            scheduleAssetRetry(identities, retryAfter: retryAfter)
        } else if let cloudError = error as? CKError {
            // quotaExceeded and other non-retryable CloudKit failures: surface
            // the real blocked reason and stop re-driving a doomed download so
            // it can't loop on backoff or resume forever on next launch.
            transferFailure = .blocked
            requiresDownloadRetry = false
            apply(error: cloudError)
        } else {
            transferFailure = .missingLocalData
            requiresDownloadRetry = true
            status = .blocked(.missingLocalData)
        }
        for identity in identities {
            snapshot.recordAssetFailure(
                transferFailure,
                recordName: identity,
                requiresDownloadRetry: requiresDownloadRetry
            )
        }
        persistSnapshot()
    }

    /// Scopes the delayed retry to the account/generation it was scheduled
    /// under. An account change during the sleep bumps the generation (or
    /// clears the confirmed account), so a stale Task no-ops instead of
    /// re-driving or dirtying the durable retry ledger for the old identity.
    private func scheduleAssetRetry(_ identities: Set<String>, retryAfter: Date?) {
        let delay = max(1, retryAfter?.timeIntervalSinceNow ?? 5)
        let account = snapshot.confirmedAccountRecordName
        let generation = snapshot.accountTransitionGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let account else { return }
            await self?.resumeScheduledRetry(identities, account: account, generation: generation)
        }
    }

    private func resumeScheduledRetry(_ identities: Set<String>, account: String, generation: Int) async {
        guard retryAccountMatches(account, generation: generation) else { return }
        for identity in identities { await requestBookAssets(contentIdentity: identity) }
    }

    private func retryAccountMatches(_ accountRecordName: String, generation: Int) -> Bool {
        !isStopped
            && !needsAccountConfirmation
            && !accountTransitionInProgress
            && snapshot.confirmedAccountRecordName == accountRecordName
            && snapshot.accountTransitionGeneration == generation
    }

    func accountState() async -> SyncAccountState {
        let lifecycle = lifecycleGeneration
        guard isActive(lifecycle), status != .disabled else { return .couldNotDetermine }
        do {
            let accountStatus = try await container.accountStatus()
            guard isActive(lifecycle) else { return .couldNotDetermine }
            switch accountStatus {
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
        guard !isStopped, needsAccountConfirmation else { return }
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
            _ = detachEngine()
            await fetchEngine.cancelOperations()
            try requireAccountTransition(generation)
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
            let assetApplication = await applyStagedAccountAssets(
                policy: policy,
                initialLocalRecords: initialLocalRecords,
                accountRecordName: finalVerification.recordName,
                transitionGeneration: generation
            )
            try requireAccountTransition(generation)
            finishTransitionAssets(assetApplication)
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
            status = BookAssetSyncStatusResolver.status(for: snapshot.bookAssetFailures)
            try persistSnapshotOrThrow()
            start()
            await resumeDurableAssetRetries()
        } catch {
            cleanupStagedDownloads(snapshot.accountTransitionRemoteAssets)
            snapshot.accountTransitionRemoteAssets = [:]
            failAccountTransitionIfActive()
            persistSnapshot()
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
        let staleEngine = detachEngine()
        if let staleEngine { Task { await staleEngine.cancelOperations() } }
        cleanupActiveUploads()
        SyncAccountTransition.quarantine(snapshot: &snapshot)
        snapshot.confirmedAccountRecordName = nil
        needsAccountConfirmation = true
        status = .accountConfirmationRequired
    }

    private func activeEngine() -> CKSyncEngine? {
        guard !isStopped, status != .disabled,
              !needsAccountConfirmation, !accountTransitionInProgress else { return nil }
        if engine == nil { start() }
        return engine
    }

    private func detachEngine() -> CKSyncEngine? {
        let detached = engine
        engine = nil
        engineActivityToken?.invalidate()
        engineActivityToken = nil
        return detached
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
        guard !isStopped else { return }
        SyncSnapshotMaintenance.prune(now: .now, snapshot: &snapshot)
        do {
            try stateStore.save(snapshot)
        } catch {
            status = .blocked(.missingLocalData)
        }
    }

    private func persistSnapshotOrThrow() throws {
        guard !isStopped else { throw SyncLifecycleError.stopped }
        SyncSnapshotMaintenance.prune(now: .now, snapshot: &snapshot)
        do {
            try stateStore.save(snapshot)
        } catch {
            status = .blocked(.missingLocalData)
            throw error
        }
    }

    private func isActive(_ generation: Int) -> Bool {
        !isStopped && lifecycleGeneration == generation
    }

    private func assetFailure(for error: Error) -> BookAssetTransferFailure {
        BookAssetFailureClassifier.classify(error)
    }

    private func recordAssetFailure(
        _ failure: BookAssetTransferFailure,
        recordName: String,
        requiresDownloadRetry: Bool = false
    ) {
        snapshot.recordAssetFailure(
            failure,
            recordName: recordName,
            requiresDownloadRetry: requiresDownloadRetry
        )
        switch failure {
        case .retryable:
            status = .waitingToRetry(nil)
        case .missingLocalData, .corrupt:
            status = .blocked(.missingLocalData)
        case .blocked:
            status = .blocked(.quotaExceeded)
        }
    }

    private func cleanupActiveUploads() {
        for stages in activeUploadAssets.values {
            for staged in stages.values { assetStaging.cleanup(staged) }
        }
        activeUploadAssets = [:]
    }

    private func takeActiveUpload(for record: CKRecord) -> BookAssetURLs? {
        guard let epubURL = LibraryRecordCodec.bookAssets(in: record)?.epub else { return nil }
        let recordName = record.recordID.recordName
        let staged = activeUploadAssets[recordName]?[epubURL.path]
        activeUploadAssets[recordName]?[epubURL.path] = nil
        if activeUploadAssets[recordName]?.isEmpty == true { activeUploadAssets[recordName] = nil }
        return staged
    }

    private func cleanupStagedDownloads(_ assets: [String: AccountOwnedBookAssets]) {
        for staged in assets.values { assetStaging.cleanup(staged.files) }
    }

    private func applyAssetOutcomes(
        _ outcomes: [String: BookAssetApplicationOutcome],
        deliveredAssets: [String: AccountOwnedBookAssets]
    ) {
        for (identity, assets) in deliveredAssets {
            guard snapshot.pendingRemoteAssets[identity] == assets else { continue }
            let shouldCleanup = snapshot.recordAssetOutcome(
                outcomes[identity] ?? .retryableFailure,
                recordName: identity,
                assets: assets
            )
            if shouldCleanup {
                assetStaging.cleanup(assets.files)
            }
        }
    }

    private func publishOwnedAssets(
        _ assets: [String: AccountOwnedBookAssets],
        accountRecordName: String,
        transitionGeneration: Int,
        scope: RemoteApplicationScope
    ) async -> [String: BookAssetApplicationOutcome] {
        let eligible = assets.filter {
            $0.value.belongs(to: accountRecordName, generation: transitionGeneration)
        }
        guard !eligible.isEmpty else { return [:] }
        let preparation = await remoteChangeHandler(
            eligible.map { .bookAssets(contentIdentity: $0.key, files: $0.value.files) },
            scope
        )
        let transactions = preparation.assetOutcomes.compactMapValues { outcome -> String? in
            guard case .provisional(let transactionID) = outcome else { return nil }
            return transactionID
        }
        guard !transactions.isEmpty else { return preparation.assetOutcomes }
        guard await verifyAssetAccount(accountRecordName, generation: transitionGeneration) else {
            _ = await rollbackProvisionalAssets(transactions, scope: scope)
            return Dictionary(uniqueKeysWithValues: eligible.keys.map { ($0, .retryableFailure) })
        }
        let finalization = await remoteChangeHandler(
            transactions.map {
                .finalizeBookAssets(contentIdentity: $0.key, transactionID: $0.value)
            },
            scope
        )
        let successfulTransactions = transactions.filter { identity, _ in
            guard case .applied = finalization.assetOutcomes[identity] else { return false }
            return true
        }
        let failedTransactions = transactions.filter { successfulTransactions[$0.key] == nil }
        _ = await rollbackProvisionalAssets(failedTransactions, scope: scope)
        guard !successfulTransactions.isEmpty else {
            return preparation.assetOutcomes.merging(finalization.assetOutcomes) { _, final in final }
        }
        guard await verifyAssetAccount(accountRecordName, generation: transitionGeneration) else {
            _ = await rollbackProvisionalAssets(successfulTransactions, scope: scope)
            return Dictionary(uniqueKeysWithValues: eligible.keys.map { ($0, .retryableFailure) })
        }
        let commitResult = await remoteChangeHandler(
            successfulTransactions.map {
                .commitBookAssets(contentIdentity: $0.key, transactionID: $0.value)
            },
            scope
        )
        let failedCommits = successfulTransactions.filter { identity, _ in
            commitResult.assetOutcomes[identity] != .committed
        }
        if !failedCommits.isEmpty { _ = await rollbackProvisionalAssets(failedCommits, scope: scope) }
        var outcomes = preparation.assetOutcomes.merging(finalization.assetOutcomes) { _, final in final }
        for identity in failedCommits.keys { outcomes[identity] = .retryableFailure }
        return outcomes
    }

    private func verifyAssetAccount(_ accountRecordName: String, generation: Int) async -> Bool {
        guard retryAccountMatches(accountRecordName, generation: generation),
              let current = try? await container.userRecordID() else { return false }
        return retryAccountMatches(accountRecordName, generation: generation)
            && current.recordName == accountRecordName
    }

    private func rollbackProvisionalAssets(
        _ transactions: [String: String],
        scope: RemoteApplicationScope
    ) async -> [String: BookAssetApplicationOutcome] {
        let result = await remoteChangeHandler(
            transactions.map {
                .rollbackBookAssets(contentIdentity: $0.key, transactionID: $0.value)
            },
            scope
        )
        return result.assetOutcomes
    }

    private func applyDeferredRemoteChanges() async {
        let lifecycle = lifecycleGeneration
        guard isActive(lifecycle) else { return }
        let assets = snapshot.pendingRemoteAssets
        let changes = snapshot.deferredRemoteDeletions.map(LibraryRemoteChange.delete)
            + snapshot.deferredRemoteRecords.values.map(LibraryRemoteChange.save)
        guard !changes.isEmpty || !assets.isEmpty else { return }
        let result = changes.isEmpty
            ? RemoteApplicationResult.complete
            : await remoteChangeHandler(changes, .normal)
        guard isActive(lifecycle) else { return }
        snapshot.deferredRemoteRecords = Dictionary(
            uniqueKeysWithValues: result.unresolvedRecords.map { ($0.reference.recordName, $0) }
        )
        snapshot.deferredRemoteDeletions = result.unresolvedDeletions
        if let accountRecordName = snapshot.confirmedAccountRecordName {
            let outcomes = await publishOwnedAssets(
                assets,
                accountRecordName: accountRecordName,
                transitionGeneration: snapshot.accountTransitionGeneration,
                scope: .normal
            )
            guard isActive(lifecycle) else { return }
            applyAssetOutcomes(outcomes, deliveredAssets: assets)
        }
        persistSnapshot()
    }
}

extension CloudKitLibrarySync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let lifecycle = lifecycleGeneration
        guard isActive(lifecycle), syncEngine === engine,
              engineActivityToken?.isActive == true else { return }
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
            await handleFetched(changes, lifecycle: lifecycle)
        case .sentRecordZoneChanges(let changes):
            handleSent(changes, syncEngine: syncEngine)
        case .sentDatabaseChanges(let changes):
            handleSentDatabaseChanges(changes, syncEngine: syncEngine)
        case .willFetchChanges, .willSendChanges:
            status = .syncing
        case .didFetchChanges, .didSendChanges:
            if !needsAccountConfirmation {
                status = BookAssetSyncStatusResolver.status(for: snapshot.bookAssetFailures)
            }
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
        let lifecycle = lifecycleGeneration
        guard isActive(lifecycle), syncEngine === engine,
              engineActivityToken?.isActive == true,
              !needsAccountConfirmation, !accountTransitionInProgress else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let pendingSaveNames = Set(pending.compactMap { change -> String? in
            guard case .saveRecord(let recordID) = change else { return nil }
            return recordID.recordName
        })
        let records = snapshot.pendingSaves
        let systemFields = snapshot.systemFields
        var assetsByRecordName: [String: BookAssetURLs] = [:]
        for (recordName, record) in records where pendingSaveNames.contains(recordName) {
            guard case .book(let book) = record else { continue }
            guard let source = await localBookAssetProvider(book), source.epub != nil else {
                guard isActive(lifecycle), syncEngine === engine else { return nil }
                recordAssetFailure(.missingLocalData, recordName: recordName)
                continue
            }
            guard isActive(lifecycle), syncEngine === engine else { return nil }
            do {
                let staged = try assetStaging.stageUpload(source, recordName: recordName)
                do {
                    try assetStaging.validateUpload(staged, identity: recordName)
                } catch {
                    assetStaging.cleanup(staged)
                    throw error
                }
                guard let epub = staged.epub else { continue }
                assetsByRecordName[recordName] = staged
                activeUploadAssets[recordName, default: [:]][epub.path] = staged
                snapshot.bookAssetFailures[recordName] = nil
            } catch {
                recordAssetFailure(assetFailure(for: error), recordName: recordName)
            }
        }
        persistSnapshot()
        let stagedAssets = assetsByRecordName
        guard let engineActivityToken, engineActivityToken.isActive else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            guard engineActivityToken.isActive else { return nil }
            guard let record = records[recordID.recordName] else { return nil }
            if case .book = record, stagedAssets[recordID.recordName]?.epub == nil { return nil }
            return try? LibraryRecordCodec.encode(
                record,
                systemFields: systemFields[recordID.recordName],
                bookAssets: stagedAssets[recordID.recordName]
            )
        }
    }

    private func handleFetched(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
        lifecycle: Int
    ) async {
        guard isActive(lifecycle), !needsAccountConfirmation else { return }
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
            if let temporaryAssets = LibraryRecordCodec.bookAssets(in: record) {
                do {
                    let staged = try assetStaging.stageDownload(
                        temporaryAssets,
                        recordName: reference.recordName
                    )
                    snapshot.pendingRemoteAssets[reference.recordName]
                        .map { assetStaging.cleanup($0.files) }
                    guard let accountRecordName = snapshot.confirmedAccountRecordName else {
                        assetStaging.cleanup(staged)
                        recordAssetFailure(.missingLocalData, recordName: reference.recordName)
                        continue
                    }
                    snapshot.pendingRemoteAssets[reference.recordName] = AccountOwnedBookAssets(
                        accountRecordName: accountRecordName,
                        transitionGeneration: snapshot.accountTransitionGeneration,
                        files: staged
                    )
                } catch {
                    let failure = assetFailure(for: error)
                    recordAssetFailure(
                        failure,
                        recordName: reference.recordName,
                        requiresDownloadRetry: true
                    )
                    if failure == .retryable { scheduleAssetRetry([reference.recordName], retryAfter: nil) }
                }
            }
        }
        for deletion in event.deletions where deletion.recordID.zoneID == LibraryRecordCodec.zoneID {
            let reference = LibraryRecordReference(
                recordType: deletion.recordType,
                recordName: deletion.recordID.recordName
            )
            FetchedRecordReconciler.applyRemoteDeletion(reference, snapshot: &snapshot)
            snapshot.pendingRemoteAssets.removeValue(forKey: reference.recordName)
                .map { assetStaging.cleanup($0.files) }
            snapshot.assetDownloadRetryRecordNames.remove(reference.recordName)
            snapshot.bookAssetFailures[reference.recordName] = nil
            SyncSnapshotMaintenance.recordTombstone(reference.recordName, at: .now, snapshot: &snapshot)
            records[reference.recordName] = nil
            deletionReferences.removeAll { $0 == reference }
            deletionReferences.append(reference)
        }
        let saves = records.values.map(LibraryRemoteChange.save)
        let deliveredAssetFiles = snapshot.pendingRemoteAssets
        let downloadedAssets = deliveredAssetFiles.map {
            LibraryRemoteChange.bookAssets(contentIdentity: $0.key, files: $0.value.files)
        }
        let metadataChanges = deletionReferences.map(LibraryRemoteChange.delete) + saves
        persistSnapshot()
        if metadataChanges.isEmpty && downloadedAssets.isEmpty {
            snapshot.deferredRemoteRecords = records
        } else {
            let result = metadataChanges.isEmpty
                ? RemoteApplicationResult.complete
                : await remoteChangeHandler(metadataChanges, .normal)
            guard isActive(lifecycle) else { return }
            snapshot.deferredRemoteRecords = Dictionary(
                uniqueKeysWithValues: result.unresolvedRecords.map { ($0.reference.recordName, $0) }
            )
            snapshot.deferredRemoteDeletions = result.unresolvedDeletions
            if let accountRecordName = snapshot.confirmedAccountRecordName {
                let assetOutcomes = await publishOwnedAssets(
                    deliveredAssetFiles,
                    accountRecordName: accountRecordName,
                    transitionGeneration: snapshot.accountTransitionGeneration,
                    scope: .normal
                )
                guard isActive(lifecycle) else { return }
                applyAssetOutcomes(assetOutcomes, deliveredAssets: deliveredAssetFiles)
            }
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
            if let temporaryAssets = LibraryRecordCodec.bookAssets(in: record) {
                do {
                    let staged = try assetStaging.stageDownload(
                        temporaryAssets,
                        recordName: decoded.reference.recordName
                    )
                    snapshot.accountTransitionRemoteAssets[decoded.reference.recordName]
                        .map { assetStaging.cleanup($0.files) }
                    guard let accountRecordName = snapshot.accountTransitionAccountRecordName else {
                        assetStaging.cleanup(staged)
                        recordAssetFailure(.missingLocalData, recordName: decoded.reference.recordName)
                        continue
                    }
                    snapshot.accountTransitionRemoteAssets[decoded.reference.recordName] = AccountOwnedBookAssets(
                        accountRecordName: accountRecordName,
                        transitionGeneration: snapshot.accountTransitionGeneration,
                        files: staged
                    )
                } catch {
                    let failure = assetFailure(for: error)
                    recordAssetFailure(
                        failure,
                        recordName: decoded.reference.recordName,
                        requiresDownloadRetry: true
                    )
                    if failure == .retryable {
                        scheduleAssetRetry([decoded.reference.recordName], retryAfter: nil)
                    }
                }
            }
        }
        for deletion in event.deletions where deletion.recordID.zoneID == LibraryRecordCodec.zoneID {
            let reference = LibraryRecordReference(
                recordType: deletion.recordType,
                recordName: deletion.recordID.recordName
            )
            snapshot.accountTransitionRemoteRecords[reference.recordName] = nil
            snapshot.accountTransitionRemoteAssets.removeValue(forKey: reference.recordName)
                .map { assetStaging.cleanup($0.files) }
            snapshot.assetDownloadRetryRecordNames.remove(reference.recordName)
            snapshot.bookAssetFailures[reference.recordName] = nil
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
            takeActiveUpload(for: record).map(assetStaging.cleanup)
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
        let stagedUpload = takeActiveUpload(for: failure.record)
        defer { stagedUpload.map(assetStaging.cleanup) }
        if failure.error.code == .serverRecordChanged,
           let serverRecord = failure.error.serverRecord,
           let remote = try? LibraryRecordCodec.decode(serverRecord),
           let local = snapshot.pendingSaves[recordID.recordName] {
            if case .book = local, let localEPUB = stagedUpload?.epub {
                guard let remoteEPUB = LibraryRecordCodec.bookAssets(in: serverRecord)?.epub else {
                    recordAssetFailure(.missingLocalData, recordName: recordID.recordName)
                    persistSnapshot()
                    return
                }
                do {
                    guard try BookAssetStaging.filesMatch(localEPUB, remoteEPUB) else {
                        recordAssetFailure(.corrupt, recordName: recordID.recordName)
                        persistSnapshot()
                        return
                    }
                } catch {
                    recordAssetFailure(.missingLocalData, recordName: recordID.recordName)
                    persistSnapshot()
                    return
                }
            }
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
        guard !isStopped else { return }
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
        cleanupStagedDownloads(snapshot.pendingRemoteAssets)
        cleanupStagedDownloads(snapshot.accountTransitionRemoteAssets)
        snapshot.pendingRemoteAssets = [:]
        snapshot.accountTransitionRemoteAssets = [:]
        cleanupActiveUploads()
        snapshot.accountTransitionGeneration += 1
        _ = detachEngine()
        snapshot.engineState = nil
        snapshot.systemFields = [:]
        snapshot.accountTransitionRemoteRecords = [:]
        snapshot.accountTransitionRemoteDeletions = []
        snapshot.accountTransitionRemoteAssets = [:]
        snapshot.accountTransitionAccountRecordName = nil
        needsAccountConfirmation = false
        accountTransitionInProgress = true
        status = .syncing
        return snapshot.accountTransitionGeneration
    }

    private func requireAccountTransition(_ generation: Int) throws {
        guard !isStopped else { throw SyncLifecycleError.stopped }
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

    private func applyStagedAccountAssets(
        policy: AccountTransitionPolicy,
        initialLocalRecords: [LibraryRecord],
        accountRecordName: String,
        transitionGeneration: Int
    ) async -> (result: RemoteApplicationResult, delivered: [String: AccountOwnedBookAssets]) {
        let metadataChanges = AccountTransitionRemoteReconciler.changes(
            records: Array(snapshot.accountTransitionRemoteRecords.values),
            deletions: snapshot.accountTransitionRemoteDeletions,
            policy: policy,
            initialLocalRecords: initialLocalRecords,
            quarantinedSaves: Array(snapshot.quarantinedSaves.values),
            quarantinedDeletes: snapshot.quarantinedDeletes
        )
        let allowedBookNames = Set(metadataChanges.compactMap { change -> String? in
            guard case .save(let record) = change, case .book = record else { return nil }
            return record.reference.recordName
        })
        let delivered = snapshot.accountTransitionRemoteAssets.filter { identity, owned in
            allowedBookNames.contains(identity)
                && owned.belongs(to: accountRecordName, generation: transitionGeneration)
        }
        guard !delivered.isEmpty else { return (.complete, [:]) }
        transitionAssetApplicationInProgress = true
        defer { transitionAssetApplicationInProgress = false }
        let outcomes = await publishOwnedAssets(
            delivered,
            accountRecordName: accountRecordName,
            transitionGeneration: transitionGeneration,
            scope: .currentAccount(
                accountRecordName: accountRecordName,
                transitionGeneration: transitionGeneration
            )
        )
        return (
            RemoteApplicationResult(
                unresolvedRecords: [],
                unresolvedDeletions: [],
                assetOutcomes: outcomes
            ),
            delivered
        )
    }

    private func finishTransitionAssets(
        _ application: (result: RemoteApplicationResult, delivered: [String: AccountOwnedBookAssets])
    ) {
        let deliveredNames = Set(application.delivered.keys)
        for (identity, owned) in snapshot.accountTransitionRemoteAssets {
            guard deliveredNames.contains(identity) else {
                assetStaging.cleanup(owned.files)
                continue
            }
            switch application.result.assetOutcomes[identity] ?? .retryableFailure {
            case .applied, .committed:
                assetStaging.cleanup(owned.files)
                snapshot.assetDownloadRetryRecordNames.remove(identity)
                snapshot.bookAssetFailures[identity] = nil
            case .provisional, .rolledBack, .retryableFailure:
                snapshot.pendingRemoteAssets[identity] = owned
                snapshot.recordAssetFailure(.retryable, recordName: identity, requiresDownloadRetry: true)
            case .unavailable:
                assetStaging.cleanup(owned.files)
                snapshot.assetDownloadRetryRecordNames.remove(identity)
                snapshot.bookAssetFailures[identity] = .corrupt
            }
        }
        snapshot.accountTransitionRemoteAssets = [:]
    }

    private func failAccountTransitionIfActive() {
        guard accountTransitionInProgress else { return }
        let staleEngine = detachEngine()
        if let staleEngine { Task { await staleEngine.cancelOperations() } }
        invalidateAccountTransition()
        persistSnapshot()
    }

    private func invalidateAccountTransition() {
        SyncCurrentAccountOperations.reQuarantine(snapshot: &snapshot)
        if !transitionAssetApplicationInProgress {
            cleanupStagedDownloads(snapshot.accountTransitionRemoteAssets)
            snapshot.accountTransitionRemoteAssets = [:]
        }
        cleanupActiveUploads()
        snapshot.accountTransitionGeneration += 1
        _ = detachEngine()
        snapshot.engineState = nil
        snapshot.systemFields = [:]
        snapshot.confirmedAccountRecordName = nil
        snapshot.accountTransitionRemoteRecords = [:]
        snapshot.accountTransitionRemoteDeletions = []
        snapshot.accountTransitionRemoteAssets = [:]
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

final class CloudSyncActivityToken: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    var isActive: Bool {
        lock.withLock { active }
    }

    func invalidate() {
        lock.withLock { active = false }
    }
}

enum SyncAccountTransitionError: Error, Equatable {
    case accountChangedDuringConfirmation
}
