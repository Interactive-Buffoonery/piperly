// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import Combine
import Foundation

@MainActor
final class ICloudSyncController: ObservableObject {
    @Published private(set) var status: LibrarySyncStatus
    @Published private(set) var confirmationContext: SyncAccountConfirmationContext?
    @Published private(set) var failedAssetIdentities: Set<String> = []
    @Published private(set) var isWorking = false
    @Published private(set) var isEnabled: Bool
    @Published var errorMessage: String?

    private let router: LibrarySyncRouter
    private let defaults: UserDefaults
    private let localSnapshotProvider: CloudKitLibrarySync.LocalSnapshotProvider
    private let localBookAssetProvider: CloudKitLibrarySync.LocalBookAssetProvider
    private let assetStagingURL: URL
    private let remoteChangeHandler: CloudKitLibrarySync.RemoteChangeHandler
    private var cloudSync: CloudKitLibrarySync?
    private var lifecycleToken: ICloudSyncLifecycleToken?

    init(
        router: LibrarySyncRouter,
        defaults: UserDefaults = .standard,
        localSnapshotProvider: @escaping CloudKitLibrarySync.LocalSnapshotProvider,
        localBookAssetProvider: @escaping CloudKitLibrarySync.LocalBookAssetProvider,
        assetStagingURL: URL,
        remoteChangeHandler: @escaping CloudKitLibrarySync.RemoteChangeHandler
    ) {
        self.router = router
        self.defaults = defaults
        self.localSnapshotProvider = localSnapshotProvider
        self.localBookAssetProvider = localBookAssetProvider
        self.assetStagingURL = assetStagingURL
        self.remoteChangeHandler = remoteChangeHandler
        let isEnabled = CloudKitLibrarySync.isEnabled(in: defaults)
        self.isEnabled = isEnabled
        status = isEnabled ? .idle : .disabled
    }

    func startIfEnabled() async {
        guard cloudSync == nil, CloudKitLibrarySync.isEnabled(in: defaults) else { return }
        await startSync()
    }

    func prepareEnable() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            await stopCurrentSync()
            let (sync, token) = try makeSync()
            cloudSync = sync
            await router.use(sync)
            guard isCurrent(sync, token: token) else { return }
            let accountState = await sync.accountState()
            guard isCurrent(sync, token: token) else { return }
            switch accountState {
            case .available:
                confirmationContext = await sync.accountConfirmationContext()
                status = .accountConfirmationRequired
            case .noAccount:
                status = .blocked(.accountUnavailable)
                errorMessage = "Sign in to iCloud in iPad Settings, then try again."
            case .restricted:
                status = .blocked(.accountRestricted)
                errorMessage = "iCloud is restricted on this iPad. Check Screen Time or account settings."
            case .temporarilyUnavailable, .couldNotDetermine:
                status = .waitingToRetry(nil)
                errorMessage = "Piperly could not reach iCloud. Check the connection and try again."
            }
        } catch {
            status = .blocked(.unknown(code: (error as NSError).code))
            errorMessage = "Piperly could not prepare iCloud sync. Your local library is unchanged."
        }
    }

    func confirmEnable(policy: AccountTransitionPolicy) async {
        guard let cloudSync, let token = lifecycleToken else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await cloudSync.confirmAccountChange(policy: policy)
            guard isCurrent(cloudSync, token: token) else { return }
            defaults.set(true, forKey: CloudKitLibrarySync.enabledDefaultsKey)
            isEnabled = true
            confirmationContext = nil
            await refreshStatus(cloudSync, token: token)
            await refreshFailedAssets()
        } catch {
            guard isCurrent(cloudSync, token: token) else { return }
            confirmationContext = await cloudSync.accountConfirmationContext()
            status = .accountConfirmationRequired
            errorMessage = "The iCloud account changed before setup finished. Nothing was uploaded. Please try again."
        }
    }

    func disable() async {
        errorMessage = nil
        isWorking = true
        await stopCurrentSync()
        defaults.set(false, forKey: CloudKitLibrarySync.enabledDefaultsKey)
        isEnabled = false
        confirmationContext = nil
        failedAssetIdentities = []
        status = .disabled
        isWorking = false
    }

    func retrySync() async {
        guard CloudKitLibrarySync.isEnabled(in: defaults), let cloudSync else {
            await prepareEnable()
            return
        }
        guard let token = lifecycleToken else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await cloudSync.syncNow()
            guard isCurrent(cloudSync, token: token) else { return }
            await refreshStatus(cloudSync, token: token)
            await refreshFailedAssets()
        } catch {
            guard isCurrent(cloudSync, token: token) else { return }
            await refreshStatus(cloudSync, token: token)
            errorMessage = "Sync could not finish. Your changes are safe on this iPad. Try again later."
        }
    }

    func retryBookAssets(contentIdentity: String) async {
        guard CloudKitLibrarySync.isEnabled(in: defaults), let cloudSync else {
            errorMessage = "Enable iCloud sync and confirm the current account before retrying a book."
            return
        }
        guard let token = lifecycleToken else { return }
        errorMessage = nil
        isWorking = true
        await cloudSync.requestBookAssets(contentIdentity: contentIdentity)
        guard isCurrent(cloudSync, token: token) else { return }
        await refreshFailedAssets()
        await refreshStatus(cloudSync, token: token)
        isWorking = false
    }

    private func startSync() async {
        guard cloudSync == nil else { return }
        do {
            let (sync, token) = try makeSync()
            cloudSync = sync
            await router.use(sync)
            guard isCurrent(sync, token: token) else { return }
            await refreshStatus(sync, token: token)
            await refreshFailedAssets()
        } catch {
            status = .blocked(.unknown(code: (error as NSError).code))
            errorMessage = "Piperly could not start iCloud sync. Your local library is unchanged."
        }
    }

    private func makeSync() throws -> (sync: CloudKitLibrarySync, token: ICloudSyncLifecycleToken) {
        let token = ICloudSyncLifecycleToken()
        lifecycleToken = token
        let sync = try CloudKitLibrarySync(
            enabled: true,
            localSnapshotProvider: localSnapshotProvider,
            localBookAssetProvider: localBookAssetProvider,
            assetStagingURL: assetStagingURL,
            statusHandler: { [weak self, token] status in
                guard token.isActive else { return }
                self?.status = status
                if status == .accountConfirmationRequired {
                    Task { await self?.loadConfirmationContext() }
                }
            },
            remoteChangeHandler: { [remoteChangeHandler, token] changes, scope in
                guard token.isActive else { return .complete }
                return remoteChangeHandler(changes, scope)
            }
        )
        return (sync, token)
    }

    private func loadConfirmationContext() async {
        guard let sync = cloudSync, let token = lifecycleToken else { return }
        let context = await sync.accountConfirmationContext()
        guard isCurrent(sync, token: token) else { return }
        confirmationContext = context
    }

    private func refreshFailedAssets() async {
        guard let sync = cloudSync, let token = lifecycleToken else { return }
        let identities = await sync.failedAssetIdentities()
        guard isCurrent(sync, token: token) else { return }
        failedAssetIdentities = identities
    }

    private func refreshStatus(
        _ sync: CloudKitLibrarySync,
        token: ICloudSyncLifecycleToken
    ) async {
        let currentStatus = await sync.currentStatus()
        guard isCurrent(sync, token: token) else { return }
        status = currentStatus
    }

    private func stopCurrentSync() async {
        lifecycleToken?.invalidate()
        lifecycleToken = nil
        await router.stop()
        if let cloudSync { await cloudSync.stop() }
        cloudSync = nil
    }

    private func isCurrent(
        _ sync: CloudKitLibrarySync,
        token: ICloudSyncLifecycleToken
    ) -> Bool {
        token.isActive && lifecycleToken === token && cloudSync === sync
    }
}

@MainActor
final class ICloudSyncLifecycleToken {
    private(set) var isActive = true

    func invalidate() {
        isActive = false
    }
}
