// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import CloudKit
import Foundation

struct SyncStateSnapshot: Codable, Sendable {
    var engineState: CKSyncEngine.State.Serialization?
    var pendingSaves: [String: LibraryRecord]
    var pendingDeletes: [LibraryRecordReference]
    var systemFields: [String: Data]
    var deferredRemoteRecords: [String: LibraryRecord]
    var deferredRemoteDeletions: [LibraryRecordReference]
    var quarantinedSaves: [String: LibraryRecord]
    var quarantinedDeletes: [LibraryRecordReference]
    var confirmedAccountRecordName: String?
    var didSeedExistingLibrary: Bool
    var accountTransitionRemoteRecords: [String: LibraryRecord]
    var accountTransitionRemoteDeletions: [LibraryRecordReference]
    var accountTransitionGeneration: Int
    var accountTransitionAccountRecordName: String?
    var currentAccountSaves: [String: LibraryRecord]
    var currentAccountDeletes: [LibraryRecordReference]
    var currentAccountRecordName: String?
    var currentAccountTransitionGeneration: Int?

    static let empty = SyncStateSnapshot(
        engineState: nil,
        pendingSaves: [:],
        pendingDeletes: [],
        systemFields: [:],
        deferredRemoteRecords: [:],
        deferredRemoteDeletions: [],
        quarantinedSaves: [:],
        quarantinedDeletes: [],
        confirmedAccountRecordName: nil,
        didSeedExistingLibrary: false,
        accountTransitionRemoteRecords: [:],
        accountTransitionRemoteDeletions: [],
        accountTransitionGeneration: 0,
        accountTransitionAccountRecordName: nil,
        currentAccountSaves: [:],
        currentAccountDeletes: [],
        currentAccountRecordName: nil,
        currentAccountTransitionGeneration: nil
    )

    private enum CodingKeys: String, CodingKey {
        case engineState, pendingSaves, pendingDeletes, systemFields
        case deferredRemoteRecords, quarantinedSaves, quarantinedDeletes, confirmedAccountRecordName
        case didSeedExistingLibrary
        case deferredRemoteDeletions, accountTransitionRemoteRecords, accountTransitionRemoteDeletions
        case accountTransitionGeneration, accountTransitionAccountRecordName
        case currentAccountSaves, currentAccountDeletes
        case currentAccountRecordName, currentAccountTransitionGeneration
    }

    init(
        engineState: CKSyncEngine.State.Serialization?,
        pendingSaves: [String: LibraryRecord],
        pendingDeletes: [LibraryRecordReference],
        systemFields: [String: Data],
        deferredRemoteRecords: [String: LibraryRecord],
        deferredRemoteDeletions: [LibraryRecordReference],
        quarantinedSaves: [String: LibraryRecord],
        quarantinedDeletes: [LibraryRecordReference],
        confirmedAccountRecordName: String?,
        didSeedExistingLibrary: Bool,
        accountTransitionRemoteRecords: [String: LibraryRecord],
        accountTransitionRemoteDeletions: [LibraryRecordReference],
        accountTransitionGeneration: Int,
        accountTransitionAccountRecordName: String?,
        currentAccountSaves: [String: LibraryRecord],
        currentAccountDeletes: [LibraryRecordReference],
        currentAccountRecordName: String?,
        currentAccountTransitionGeneration: Int?
    ) {
        self.engineState = engineState
        self.pendingSaves = pendingSaves
        self.pendingDeletes = pendingDeletes
        self.systemFields = systemFields
        self.deferredRemoteRecords = deferredRemoteRecords
        self.deferredRemoteDeletions = deferredRemoteDeletions
        self.quarantinedSaves = quarantinedSaves
        self.quarantinedDeletes = quarantinedDeletes
        self.confirmedAccountRecordName = confirmedAccountRecordName
        self.didSeedExistingLibrary = didSeedExistingLibrary
        self.accountTransitionRemoteRecords = accountTransitionRemoteRecords
        self.accountTransitionRemoteDeletions = accountTransitionRemoteDeletions
        self.accountTransitionGeneration = accountTransitionGeneration
        self.accountTransitionAccountRecordName = accountTransitionAccountRecordName
        self.currentAccountSaves = currentAccountSaves
        self.currentAccountDeletes = currentAccountDeletes
        self.currentAccountRecordName = currentAccountRecordName
        self.currentAccountTransitionGeneration = currentAccountTransitionGeneration
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
