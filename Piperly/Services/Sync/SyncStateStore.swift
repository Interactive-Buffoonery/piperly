// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import CloudKit
import Foundation

enum BookAssetTransferFailure: String, Codable, Sendable, Equatable {
    case retryable
    case missingLocalData
    case corrupt
}

struct AccountOwnedBookAssets: Codable, Sendable, Equatable {
    let accountRecordName: String
    let transitionGeneration: Int
    let files: BookAssetURLs

    func belongs(to accountRecordName: String, generation: Int) -> Bool {
        self.accountRecordName == accountRecordName && transitionGeneration == generation
    }
}

struct SyncStateSnapshot: Codable, Sendable {
    var engineState: CKSyncEngine.State.Serialization?
    var pendingSaves: [String: LibraryRecord]
    var pendingDeletes: [LibraryRecordReference]
    var systemFields: [String: Data]
    var deferredRemoteRecords: [String: LibraryRecord]
    var deferredRemoteDeletions: [LibraryRecordReference]
    var pendingRemoteAssets: [String: AccountOwnedBookAssets]
    var assetDownloadRetryRecordNames: Set<String>
    var bookAssetFailures: [String: BookAssetTransferFailure]
    var quarantinedSaves: [String: LibraryRecord]
    var quarantinedDeletes: [LibraryRecordReference]
    var confirmedAccountRecordName: String?
    var didSeedExistingLibrary: Bool
    var accountTransitionRemoteRecords: [String: LibraryRecord]
    var accountTransitionRemoteDeletions: [LibraryRecordReference]
    var accountTransitionRemoteAssets: [String: AccountOwnedBookAssets]
    var accountTransitionGeneration: Int
    var accountTransitionAccountRecordName: String?
    var currentAccountSaves: [String: LibraryRecord]
    var currentAccountDeletes: [LibraryRecordReference]
    var currentAccountRecordName: String?
    var currentAccountTransitionGeneration: Int?
    var tombstones: [String: Date]

    static let empty = SyncStateSnapshot(
        engineState: nil,
        pendingSaves: [:],
        pendingDeletes: [],
        systemFields: [:],
        deferredRemoteRecords: [:],
        deferredRemoteDeletions: [],
        pendingRemoteAssets: [:],
        assetDownloadRetryRecordNames: [],
        bookAssetFailures: [:],
        quarantinedSaves: [:],
        quarantinedDeletes: [],
        confirmedAccountRecordName: nil,
        didSeedExistingLibrary: false,
        accountTransitionRemoteRecords: [:],
        accountTransitionRemoteDeletions: [],
        accountTransitionRemoteAssets: [:],
        accountTransitionGeneration: 0,
        accountTransitionAccountRecordName: nil,
        currentAccountSaves: [:],
        currentAccountDeletes: [],
        currentAccountRecordName: nil,
        currentAccountTransitionGeneration: nil,
        tombstones: [:]
    )

    private enum CodingKeys: String, CodingKey {
        case engineState, pendingSaves, pendingDeletes, systemFields
        case deferredRemoteRecords, quarantinedSaves, quarantinedDeletes, confirmedAccountRecordName
        case didSeedExistingLibrary
        case deferredRemoteDeletions, accountTransitionRemoteRecords, accountTransitionRemoteDeletions
        case pendingRemoteAssets, assetDownloadRetryRecordNames, bookAssetFailures
        case accountTransitionRemoteAssets
        case accountTransitionGeneration, accountTransitionAccountRecordName
        case currentAccountSaves, currentAccountDeletes
        case currentAccountRecordName, currentAccountTransitionGeneration
        case tombstones
    }

    init(
        engineState: CKSyncEngine.State.Serialization?,
        pendingSaves: [String: LibraryRecord],
        pendingDeletes: [LibraryRecordReference],
        systemFields: [String: Data],
        deferredRemoteRecords: [String: LibraryRecord],
        deferredRemoteDeletions: [LibraryRecordReference],
        pendingRemoteAssets: [String: AccountOwnedBookAssets],
        assetDownloadRetryRecordNames: Set<String>,
        bookAssetFailures: [String: BookAssetTransferFailure],
        quarantinedSaves: [String: LibraryRecord],
        quarantinedDeletes: [LibraryRecordReference],
        confirmedAccountRecordName: String?,
        didSeedExistingLibrary: Bool,
        accountTransitionRemoteRecords: [String: LibraryRecord],
        accountTransitionRemoteDeletions: [LibraryRecordReference],
        accountTransitionRemoteAssets: [String: AccountOwnedBookAssets],
        accountTransitionGeneration: Int,
        accountTransitionAccountRecordName: String?,
        currentAccountSaves: [String: LibraryRecord],
        currentAccountDeletes: [LibraryRecordReference],
        currentAccountRecordName: String?,
        currentAccountTransitionGeneration: Int?,
        tombstones: [String: Date] = [:]
    ) {
        self.engineState = engineState
        self.pendingSaves = pendingSaves
        self.pendingDeletes = pendingDeletes
        self.systemFields = systemFields
        self.deferredRemoteRecords = deferredRemoteRecords
        self.deferredRemoteDeletions = deferredRemoteDeletions
        self.pendingRemoteAssets = pendingRemoteAssets
        self.assetDownloadRetryRecordNames = assetDownloadRetryRecordNames
        self.bookAssetFailures = bookAssetFailures
        self.quarantinedSaves = quarantinedSaves
        self.quarantinedDeletes = quarantinedDeletes
        self.confirmedAccountRecordName = confirmedAccountRecordName
        self.didSeedExistingLibrary = didSeedExistingLibrary
        self.accountTransitionRemoteRecords = accountTransitionRemoteRecords
        self.accountTransitionRemoteDeletions = accountTransitionRemoteDeletions
        self.accountTransitionRemoteAssets = accountTransitionRemoteAssets
        self.accountTransitionGeneration = accountTransitionGeneration
        self.accountTransitionAccountRecordName = accountTransitionAccountRecordName
        self.currentAccountSaves = currentAccountSaves
        self.currentAccountDeletes = currentAccountDeletes
        self.currentAccountRecordName = currentAccountRecordName
        self.currentAccountTransitionGeneration = currentAccountTransitionGeneration
        self.tombstones = tombstones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engineState = try container.decodeIfPresent(CKSyncEngine.State.Serialization.self, forKey: .engineState)
        pendingSaves = try container.decodeIfPresent([String: LibraryRecord].self, forKey: .pendingSaves) ?? [:]
        pendingDeletes = try container.decodeIfPresent([LibraryRecordReference].self, forKey: .pendingDeletes) ?? []
        systemFields = try container.decodeIfPresent([String: Data].self, forKey: .systemFields) ?? [:]
        deferredRemoteRecords = try container.decodeIfPresent(
            [String: LibraryRecord].self,
            forKey: .deferredRemoteRecords
        ) ?? [:]
        deferredRemoteDeletions = try container.decodeIfPresent(
            [LibraryRecordReference].self,
            forKey: .deferredRemoteDeletions
        ) ?? []
        pendingRemoteAssets = try container.decodeIfPresent(
            [String: AccountOwnedBookAssets].self,
            forKey: .pendingRemoteAssets
        ) ?? [:]
        assetDownloadRetryRecordNames = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .assetDownloadRetryRecordNames
        ) ?? []
        bookAssetFailures = try container.decodeIfPresent(
            [String: BookAssetTransferFailure].self,
            forKey: .bookAssetFailures
        ) ?? [:]
        quarantinedSaves = try container.decodeIfPresent(
            [String: LibraryRecord].self,
            forKey: .quarantinedSaves
        ) ?? [:]
        quarantinedDeletes = try container.decodeIfPresent(
            [LibraryRecordReference].self,
            forKey: .quarantinedDeletes
        ) ?? []
        confirmedAccountRecordName = try container.decodeIfPresent(
            String.self,
            forKey: .confirmedAccountRecordName
        )
        didSeedExistingLibrary = try container.decodeIfPresent(Bool.self, forKey: .didSeedExistingLibrary)
            ?? false
        accountTransitionRemoteRecords = try container.decodeIfPresent(
            [String: LibraryRecord].self,
            forKey: .accountTransitionRemoteRecords
        ) ?? [:]
        accountTransitionRemoteDeletions = try container.decodeIfPresent(
            [LibraryRecordReference].self,
            forKey: .accountTransitionRemoteDeletions
        ) ?? []
        accountTransitionRemoteAssets = try container.decodeIfPresent(
            [String: AccountOwnedBookAssets].self,
            forKey: .accountTransitionRemoteAssets
        ) ?? [:]
        accountTransitionGeneration = try container.decodeIfPresent(
            Int.self,
            forKey: .accountTransitionGeneration
        ) ?? 0
        accountTransitionAccountRecordName = try container.decodeIfPresent(
            String.self,
            forKey: .accountTransitionAccountRecordName
        )
        currentAccountSaves = try container.decodeIfPresent(
            [String: LibraryRecord].self,
            forKey: .currentAccountSaves
        ) ?? [:]
        currentAccountDeletes = try container.decodeIfPresent(
            [LibraryRecordReference].self,
            forKey: .currentAccountDeletes
        ) ?? []
        currentAccountRecordName = try container.decodeIfPresent(
            String.self,
            forKey: .currentAccountRecordName
        )
        currentAccountTransitionGeneration = try container.decodeIfPresent(
            Int.self,
            forKey: .currentAccountTransitionGeneration
        )
        tombstones = try container.decodeIfPresent([String: Date].self, forKey: .tombstones) ?? [:]
    }
}

extension SyncStateSnapshot {
    mutating func recordAssetFailure(
        _ failure: BookAssetTransferFailure,
        recordName: String,
        requiresDownloadRetry: Bool = false
    ) {
        bookAssetFailures[recordName] = failure
        if requiresDownloadRetry { assetDownloadRetryRecordNames.insert(recordName) }
    }

    mutating func recordAssetOutcome(
        _ outcome: BookAssetApplicationOutcome,
        recordName: String,
        assets: AccountOwnedBookAssets
    ) -> Bool {
        switch outcome {
        case .provisional, .rolledBack:
            pendingRemoteAssets[recordName] = assets
            return false
        case .applied, .committed:
            pendingRemoteAssets[recordName] = nil
            assetDownloadRetryRecordNames.remove(recordName)
            bookAssetFailures[recordName] = nil
            return true
        case .retryableFailure:
            pendingRemoteAssets[recordName] = assets
            recordAssetFailure(.retryable, recordName: recordName, requiresDownloadRetry: true)
            return false
        case .unavailable:
            pendingRemoteAssets[recordName] = nil
            assetDownloadRetryRecordNames.remove(recordName)
            bookAssetFailures[recordName] = .corrupt
            return true
        }
    }
}

struct SyncStateStore: Sendable {
    let fileURL: URL

    func load() throws -> SyncStateSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        return try JSONDecoder().decode(SyncStateSnapshot.self, from: Data(contentsOf: fileURL))
    }

    func save(_ snapshot: SyncStateSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(snapshot).write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func reset() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

struct LibraryOutboxStore: Sendable {
    let fileURL: URL

    static let defaultURL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0]
        .appendingPathComponent("Piperly", isDirectory: true)
        .appendingPathComponent("LibrarySyncOutbox.json")

    func load() throws -> [LibraryOutboxOperation] {
        do {
            return try JSONDecoder().decode([LibraryOutboxOperation].self, from: Data(contentsOf: fileURL))
        } catch {
            let fileError = error as NSError
            if fileError.domain == NSCocoaErrorDomain,
               fileError.code == NSFileReadNoSuchFileError {
                return []
            }
            throw error
        }
    }

    func save(_ operations: [LibraryOutboxOperation]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(operations).write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}
