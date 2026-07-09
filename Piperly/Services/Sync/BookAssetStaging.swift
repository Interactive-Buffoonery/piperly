// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import CryptoKit
import Foundation

enum BookAssetAvailability: Codable, Sendable, Equatable {
    case local
    case uploading
    case downloading
    case remoteOnly
    case retryableFailure
    case unavailable
}

struct BookAssetURLs: Codable, Sendable, Equatable {
    let epub: URL?
    let cover: URL?
}

struct PublishedBookAssets: Sendable, Equatable {
    let createdEPUB: Bool
    let createdCover: Bool
}

enum BookAssetError: Error, Equatable {
    case missingEPUB
    case hashMismatch
    case contentIdentityCollision
}

enum BookAssetFailureClassifier {
    static func classify(_ error: Error) -> BookAssetTransferFailure {
        if let assetError = error as? BookAssetError {
            switch assetError {
            case .missingEPUB: return .missingLocalData
            case .hashMismatch, .contentIdentityCollision: return .corrupt
            }
        }
        let fileError = error as NSError
        if fileError.domain == NSCocoaErrorDomain,
           [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(fileError.code) {
            return .missingLocalData
        }
        return .retryable
    }
}

final class BookAssetStaging: @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func stageUpload(_ source: BookAssetURLs, recordName: String) throws -> BookAssetURLs {
        let directory = rootURL.appendingPathComponent("upload-\(recordName)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let epub = try source.epub.map { try copy($0, to: directory.appendingPathComponent("book.epub")) }
            let cover = try source.cover.map { try copy($0, to: directory.appendingPathComponent("cover.jpg")) }
            return BookAssetURLs(epub: epub, cover: cover)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func stageDownload(_ source: BookAssetURLs, recordName: String) throws -> BookAssetURLs {
        let directory = rootURL.appendingPathComponent("download-\(recordName)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let epub = try source.epub.map { try copy($0, to: directory.appendingPathComponent("book.epub")) }
            let cover = try source.cover.map { try copy($0, to: directory.appendingPathComponent("cover.jpg")) }
            return BookAssetURLs(epub: epub, cover: cover)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func publishDownload(
        _ staged: BookAssetURLs,
        identity: String,
        epubDestination: URL,
        coverDestination: URL?
    ) throws -> PublishedBookAssets {
        guard let stagedEPUB = staged.epub else { throw BookAssetError.missingEPUB }
        guard try Self.sha256(of: stagedEPUB) == identity.lowercased() else {
            throw BookAssetError.hashMismatch
        }
        let createdEPUB = !fileManager.fileExists(atPath: epubDestination.path)
        if !createdEPUB {
            guard try Self.filesMatch(stagedEPUB, epubDestination) else {
                throw BookAssetError.contentIdentityCollision
            }
        } else {
            try fileManager.createDirectory(
                at: epubDestination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: stagedEPUB, to: epubDestination)
        }
        var createdCover = false
        if let stagedCover = staged.cover, let coverDestination {
            try fileManager.createDirectory(
                at: coverDestination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            createdCover = !fileManager.fileExists(atPath: coverDestination.path)
            if createdCover {
                try fileManager.moveItem(at: stagedCover, to: coverDestination)
            }
        }
        cleanup(staged)
        return PublishedBookAssets(createdEPUB: createdEPUB, createdCover: createdCover)
    }

    func validateUpload(_ staged: BookAssetURLs, identity: String) throws {
        guard let epub = staged.epub else { throw BookAssetError.missingEPUB }
        guard try Self.sha256(of: epub) == identity.lowercased() else {
            throw BookAssetError.hashMismatch
        }
    }

    func cleanup(_ staged: BookAssetURLs) {
        let candidate = staged.epub ?? staged.cover
        guard let directory = candidate?.deletingLastPathComponent(),
              directory.deletingLastPathComponent().resolvingSymlinksInPath().path
                == rootURL.resolvingSymlinksInPath().path else { return }
        try? fileManager.removeItem(at: directory)
    }

    func clearStaleFiles(retaining retainedFiles: Set<URL> = []) {
        let retainedDirectories = Set(retainedFiles.map {
            $0.deletingLastPathComponent().resolvingSymlinksInPath().path
        })
        guard let contents = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where !retainedDirectories.contains(url.resolvingSymlinksInPath().path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func copy(_ source: URL, to destination: URL) throws -> URL {
        guard fileManager.fileExists(atPath: source.path) else { throw BookAssetError.missingEPUB }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func filesMatch(_ first: URL, _ second: URL) throws -> Bool {
        let firstHandle = try FileHandle(forReadingFrom: first)
        defer { try? firstHandle.close() }
        let secondHandle = try FileHandle(forReadingFrom: second)
        defer { try? secondHandle.close() }
        while true {
            let firstData = try firstHandle.read(upToCount: 1_048_576)
            let secondData = try secondHandle.read(upToCount: 1_048_576)
            guard firstData == secondData else { return false }
            guard let firstData, !firstData.isEmpty else { return true }
        }
    }
}

final class ProvisionalBookAssetStore {
    private struct Transaction: Codable {
        enum State: String, Codable { case prepared, finalized, committed }
        let id: String
        let identity: String
        let epubDestination: URL
        let coverDestination: URL?
        var state: State
        var createdEPUB: Bool
        var createdCover: Bool
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private let removeItem: (URL) throws -> Void
    private var activeTransactions: Set<String> = []

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        removeItem: ((URL) throws -> Void)? = nil
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.removeItem = removeItem ?? { try fileManager.removeItem(at: $0) }
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        rollbackInterruptedTransactions()
    }

    func prepare(
        files: BookAssetURLs,
        identity: String,
        epubDestination: URL,
        coverDestination: URL?
    ) throws -> String {
        rollbackInterruptedTransactions()
        let unresolved = (try? fileManager.contentsOfDirectory(atPath: rootURL.path))?
            .filter { !activeTransactions.contains($0) } ?? []
        guard unresolved.isEmpty else {
            throw BookAssetError.missingEPUB
        }
        guard let epub = files.epub else { throw BookAssetError.missingEPUB }
        guard try BookAssetStaging.sha256(of: epub) == identity.lowercased() else {
            throw BookAssetError.hashMismatch
        }
        let id = UUID().uuidString
        let directory = transactionURL(id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try fileManager.copyItem(at: epub, to: directory.appendingPathComponent("book.epub"))
            if let cover = files.cover {
                try fileManager.copyItem(at: cover, to: directory.appendingPathComponent("cover.jpg"))
            }
            try save(Transaction(
                id: id,
                identity: identity,
                epubDestination: epubDestination,
                coverDestination: coverDestination,
                state: .prepared,
                createdEPUB: false,
                createdCover: false
            ))
            activeTransactions.insert(id)
            return id
        } catch {
            try? removeItem(directory)
            throw error
        }
    }

    func finalize(_ id: String) throws -> PublishedBookAssets {
        var transaction = try load(id)
        let stagedEPUB = transactionURL(id).appendingPathComponent("book.epub")
        let createdEPUB = !fileManager.fileExists(atPath: transaction.epubDestination.path)
        let stagedCover = transactionURL(id).appendingPathComponent("cover.jpg")
        let hasCover = fileManager.fileExists(atPath: stagedCover.path)
        let createdCover = hasCover && transaction.coverDestination.map {
            !fileManager.fileExists(atPath: $0.path)
        } == true
        transaction.state = .finalized
        transaction.createdEPUB = createdEPUB
        transaction.createdCover = createdCover
        try save(transaction)

        if createdEPUB {
            try fileManager.createDirectory(
                at: transaction.epubDestination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: stagedEPUB, to: transaction.epubDestination)
        } else if try !BookAssetStaging.filesMatch(stagedEPUB, transaction.epubDestination) {
            throw BookAssetError.contentIdentityCollision
        }
        if createdCover, let destination = transaction.coverDestination {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: stagedCover, to: destination)
        }
        return PublishedBookAssets(createdEPUB: createdEPUB, createdCover: createdCover)
    }

    func commit(_ id: String) throws {
        var transaction = try load(id)
        transaction.state = .committed
        try save(transaction)
        activeTransactions.remove(id)
        try? removeItem(transactionURL(id))
    }

    func rollback(_ id: String) throws {
        activeTransactions.remove(id)
        let transaction = try load(id)
        if transaction.state == .committed {
            try removeItem(transactionURL(id))
            return
        }
        if transaction.state == .finalized {
            if transaction.createdEPUB, fileManager.fileExists(atPath: transaction.epubDestination.path) {
                try removeItem(transaction.epubDestination)
            }
            if transaction.createdCover, let cover = transaction.coverDestination {
                if fileManager.fileExists(atPath: cover.path) { try removeItem(cover) }
            }
        }
        let epubIsAbsent = !fileManager.fileExists(atPath: transaction.epubDestination.path)
        let coverIsAbsent = transaction.coverDestination.map {
            !fileManager.fileExists(atPath: $0.path)
        } ?? true
        guard !transaction.createdEPUB || epubIsAbsent,
              !transaction.createdCover || coverIsAbsent else {
            throw BookAssetError.missingEPUB
        }
        try removeItem(transactionURL(id))
    }

    private func rollbackInterruptedTransactions() {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for directory in directories where !activeTransactions.contains(directory.lastPathComponent) {
            try? rollback(directory.lastPathComponent)
        }
    }

    private func transactionURL(_ id: String) -> URL {
        rootURL.appendingPathComponent(id, isDirectory: true)
    }

    private func save(_ transaction: Transaction) throws {
        try JSONEncoder().encode(transaction).write(
            to: transactionURL(transaction.id).appendingPathComponent("transaction.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func load(_ id: String) throws -> Transaction {
        try JSONDecoder().decode(
            Transaction.self,
            from: Data(contentsOf: transactionURL(id).appendingPathComponent("transaction.json"))
        )
    }
}
