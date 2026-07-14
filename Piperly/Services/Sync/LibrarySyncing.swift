// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import Foundation

protocol LibrarySyncing: Sendable {
    func enqueue(_ operations: [LibraryOutboxOperation]) throws
    func flush() throws
    func currentOutboxStatus() -> LibraryOutboxStatus
}

extension LibrarySyncing {
    func currentOutboxStatus() -> LibraryOutboxStatus { .ready }

    func enqueueSave(_ record: LibraryRecord) throws {
        try enqueue([.save(record)])
    }

    func enqueueDelete(_ reference: LibraryRecordReference) throws {
        try enqueue([.delete(reference)])
    }
}

protocol LibrarySyncSink: Sendable {
    func acceptSave(_ record: LibraryRecord, scope: RemoteApplicationScope) async throws
    func acceptDelete(_ reference: LibraryRecordReference, scope: RemoteApplicationScope) async throws
}

struct RemoteApplicationScope: Codable, Sendable, Equatable {
    let accountRecordName: String?
    let transitionGeneration: Int?

    static let normal = RemoteApplicationScope(
        accountRecordName: nil,
        transitionGeneration: nil
    )

    static func currentAccount(
        accountRecordName: String,
        transitionGeneration: Int
    ) -> RemoteApplicationScope {
        RemoteApplicationScope(
            accountRecordName: accountRecordName,
            transitionGeneration: transitionGeneration
        )
    }

    var isCurrentAccount: Bool {
        accountRecordName != nil && transitionGeneration != nil
    }
}

enum LibraryRemoteChange: Sendable, Equatable {
    case save(LibraryRecord)
    case delete(LibraryRecordReference)
}

struct RemoteApplicationResult: Sendable, Equatable {
    let unresolvedRecords: [LibraryRecord]
    let unresolvedDeletions: [LibraryRecordReference]

    static let complete = RemoteApplicationResult(unresolvedRecords: [], unresolvedDeletions: [])
}

struct DisabledLibrarySync: LibrarySyncing {
    func enqueue(_ operations: [LibraryOutboxOperation]) throws {}
    func flush() throws {}
}

enum LibraryOutboxStatus: Sendable, Equatable {
    case ready
    case blocked
}

enum LibraryOutboxError: Error, Equatable {
    case unavailable
}

struct LibraryOutboxOperation: Codable, Sendable, Equatable {
    enum Intent: String, Codable, Sendable {
        case save
        case delete
    }

    let intent: Intent
    let reference: LibraryRecordReference
    let record: LibraryRecord?
    let scope: RemoteApplicationScope?

    var effectiveScope: RemoteApplicationScope { scope ?? .normal }

    static func save(_ record: LibraryRecord) -> LibraryOutboxOperation {
        LibraryOutboxOperation(intent: .save, reference: record.reference, record: record, scope: nil)
    }

    static func delete(_ reference: LibraryRecordReference) -> LibraryOutboxOperation {
        LibraryOutboxOperation(intent: .delete, reference: reference, record: nil, scope: nil)
    }
}

private final class LockedLibraryOutbox: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let store: LibraryOutboxStore
    private var operations: [LibraryOutboxOperation]
    private var failure: Error?
    private var currentAccountScopes: [RemoteApplicationScope] = []

    init(store: LibraryOutboxStore) {
        self.store = store
        do {
            operations = try store.load()
            failure = nil
        } catch {
            operations = []
            failure = error
        }
    }

    func append(_ newOperations: [LibraryOutboxOperation]) throws {
        try lock.withLock {
            guard failure == nil else { throw LibraryOutboxError.unavailable }
            var updated = operations
            for originalOperation in newOperations {
                let operation = currentAccountScopes.last.map { scope in
                    LibraryOutboxOperation(
                        intent: originalOperation.intent,
                        reference: originalOperation.reference,
                        record: originalOperation.record,
                        scope: scope
                    )
                } ?? originalOperation
                updated.removeAll { $0.reference == operation.reference }
                updated.append(operation)
            }
            do {
                try store.save(updated)
            } catch {
                failure = error
                throw LibraryOutboxError.unavailable
            }
            operations = updated
        }
    }

    func first() -> LibraryOutboxOperation? {
        lock.withLock { operations.first }
    }

    func removeFirst(ifMatching operation: LibraryOutboxOperation) throws {
        try lock.withLock {
            guard failure == nil else { throw LibraryOutboxError.unavailable }
            guard operations.first == operation else { return }
            let updated = Array(operations.dropFirst())
            do {
                try store.save(updated)
            } catch {
                failure = error
                throw LibraryOutboxError.unavailable
            }
            operations = updated
        }
    }

    func flush() throws {
        try lock.withLock {
            guard failure == nil else { throw LibraryOutboxError.unavailable }
            do {
                try store.save(operations)
            } catch {
                failure = error
                throw LibraryOutboxError.unavailable
            }
        }
    }

    func snapshot() -> [LibraryOutboxOperation] {
        lock.withLock { operations }
    }

    func status() -> LibraryOutboxStatus {
        lock.withLock { failure == nil ? .ready : .blocked }
    }

    func applyingCurrentAccountChanges(
        scope: RemoteApplicationScope,
        _ body: () -> RemoteApplicationResult
    ) -> RemoteApplicationResult {
        lock.withLock { currentAccountScopes.append(scope) }
        defer { lock.withLock { _ = currentAccountScopes.popLast() } }
        return body()
    }
}

actor LibrarySyncRouter: LibrarySyncing {
    nonisolated private let outbox: LockedLibraryOutbox
    private var target: (any LibrarySyncSink)?

    init(fileURL: URL = LibraryOutboxStore.defaultURL) {
        outbox = LockedLibraryOutbox(store: LibraryOutboxStore(fileURL: fileURL))
    }

    func use(_ target: any LibrarySyncSink) async {
        self.target = target
        await drain()
    }

    nonisolated func enqueue(_ operations: [LibraryOutboxOperation]) throws {
        try outbox.append(operations)
        Task { await self.drain() }
    }

    nonisolated func flush() throws {
        try outbox.flush()
    }

    nonisolated func pendingOperations() -> [LibraryOutboxOperation] {
        outbox.snapshot()
    }

    nonisolated func outboxStatus() -> LibraryOutboxStatus {
        outbox.status()
    }

    nonisolated func currentOutboxStatus() -> LibraryOutboxStatus {
        outbox.status()
    }

    nonisolated func applyingCurrentAccountChanges(
        scope: RemoteApplicationScope,
        _ body: () -> RemoteApplicationResult
    ) -> RemoteApplicationResult {
        outbox.applyingCurrentAccountChanges(scope: scope, body)
    }

    private func drain() async {
        guard let target else { return }
        while let operation = outbox.first() {
            do {
                switch operation.intent {
                case .save:
                    guard let record = operation.record else { return }
                    try await target.acceptSave(record, scope: operation.effectiveScope)
                case .delete:
                    try await target.acceptDelete(operation.reference, scope: operation.effectiveScope)
                }
                try outbox.removeFirst(ifMatching: operation)
            } catch {
                return
            }
        }
    }
}

final class FakeLibrarySync: LibrarySyncing, @unchecked Sendable {
    private let lock = NSLock()
    private var savedRecords: [LibraryRecord] = []
    private var deletedRecords: [LibraryRecordReference] = []

    func enqueue(_ operations: [LibraryOutboxOperation]) throws {
        lock.withLock {
            for operation in operations {
                savedRecords.removeAll { $0.reference == operation.reference }
                deletedRecords.removeAll { $0 == operation.reference }
                if let record = operation.record {
                    savedRecords.append(record)
                } else {
                    deletedRecords.append(operation.reference)
                }
            }
        }
    }

    func flush() throws {}

    func snapshot() -> (saved: [LibraryRecord], deleted: [LibraryRecordReference]) {
        lock.withLock { (savedRecords, deletedRecords) }
    }
}
