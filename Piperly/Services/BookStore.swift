// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import CryptoKit
import Foundation
import SwiftUI
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer

// swiftlint:disable file_length
@MainActor
// swiftlint:disable:next type_body_length
class BookStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var profiles: [ReaderProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var readingStates: [ReadingState] = []
    @Published var bookmarks: [Bookmark] = []
    @Published var savedWords: [SavedWord] = []
    @Published private(set) var syncOutboxStatus: LibraryOutboxStatus = .ready

    private let documentsURL: URL
    private let coversURL: URL
    private let importSnapshotsURL: URL
    private let userDefaults: UserDefaults
    private let librarySync: any LibrarySyncing
    private let booksKey = "piperly_books"
    private let profilesKey = "piperly_reader_profiles"
    private let selectedProfileKey = "piperly_selected_profile_id"
    private let readingStatesKey = "piperly_reading_states"
    private let bookmarksKey = "piperly_bookmarks"
    private let savedWordsKey = "piperly_saved_words"
    private var debouncedBooksSave: Task<Void, Never>?
    private var debouncedReadingStatesSave: Task<Void, Never>?
    private var debouncedWordsSave: Task<Void, Never>?
    private var importsByContentIdentity: [String: Task<Book, Error>] = [:]
    nonisolated private static let fileReadChunkSize = 1_048_576

    /// Keys whose persisted bytes were non-empty but decoded to nothing (total
    /// corruption). We refuse to overwrite them with an empty array so a bad
    /// upgrade can't erase recoverable data. Cleared once real data returns.
    private var corruptedStoreKeys: Set<String> = []

    /// Element-wise tolerant array decode: skips individual records that fail
    /// (legacy/corrupt) instead of dropping the whole array. Flags total loss
    /// so `persistArray` won't clobber the bytes.
    private func loadArray<T: Decodable>(_ type: T.Type, forKey key: String) -> [T]? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        if let decoded = try? JSONDecoder().decode([T].self, from: data) {
            corruptedStoreKeys.remove(key)
            return decoded
        }
        // Whole-array decode failed on one bad element; recover the rest.
        var recovered: [T] = []
        if let raw = try? JSONDecoder().decode([FailableCodable<T>].self, from: data) {
            recovered = raw.compactMap(\.value)
        }
        if recovered.isEmpty && !data.isEmpty {
            corruptedStoreKeys.insert(key)
        } else {
            corruptedStoreKeys.remove(key)
        }
        return recovered
    }

    /// Legacy records persisted before profiles existed decode with a sentinel
    /// `profileID`; rehome them onto the active profile so they survive upgrade
    /// instead of being orphaned.
    private func backfillProfileID<T: ProfileScoped>(_ values: [T]) -> [T] {
        let active = activeProfileID
        return values.map { $0.profileID == ProfileScopedDefaults.legacyProfileID ? $0.withProfileID(active) : $0 }
    }

    private func persistArray<T: Encodable>(_ values: [T], forKey key: String) {
        if values.isEmpty && corruptedStoreKeys.contains(key) { return }
        if !values.isEmpty { corruptedStoreKeys.remove(key) }
        if let data = try? JSONEncoder().encode(values) {
            userDefaults.set(data, forKey: key)
        }
    }

    convenience init(
        userDefaults: UserDefaults = .standard,
        librarySync: any LibrarySyncing = DisabledLibrarySync()
    ) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(
            documentsURL: docs.appendingPathComponent("Books", isDirectory: true),
            coversURL: docs.appendingPathComponent("Covers", isDirectory: true),
            userDefaults: userDefaults,
            librarySync: librarySync
        )
    }

    init(
        documentsURL: URL,
        coversURL: URL,
        userDefaults: UserDefaults,
        librarySync: any LibrarySyncing = DisabledLibrarySync()
    ) {
        self.documentsURL = documentsURL
        self.coversURL = coversURL
        self.importSnapshotsURL = documentsURL.deletingLastPathComponent()
            .appendingPathComponent(".PiperlyImportSnapshots", isDirectory: true)
        self.userDefaults = userDefaults
        self.librarySync = librarySync
        self.syncOutboxStatus = librarySync.currentOutboxStatus()

        try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: coversURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: importSnapshotsURL, withIntermediateDirectories: true)
        Self.clearStaleSnapshots(in: importSnapshotsURL)
        Self.excludeFromBackup(documentsURL)
        Self.excludeFromBackup(coversURL)
        Self.excludeFromBackup(importSnapshotsURL)
        loadBooks()
        loadProfiles()
        loadSelectedProfileID()
        ensureDefaultProfile()
        loadReadingStates()
        loadBookmarks()
        loadSavedWords()
    }

    /// Books are re-importable and covers are re-derivable via `backfillCovers()`,
    /// so neither belongs in iCloud backups (Apple Data Storage Guidelines).
    nonisolated private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    func loadBooks() {
        guard let saved = loadArray(Book.self, forKey: booksKey) else { return }
        books = saved
    }

    func saveBooks() {
        persistArray(books, forKey: booksKey)
    }

    func loadProfiles() {
        guard let saved = loadArray(ReaderProfile.self, forKey: profilesKey) else { return }
        profiles = saved
    }

    func saveProfiles() {
        persistArray(profiles, forKey: profilesKey)
    }

    func loadSelectedProfileID() {
        guard let rawValue = userDefaults.string(forKey: selectedProfileKey),
              let id = UUID(uuidString: rawValue) else {
            return
        }
        selectedProfileID = id
    }

    func saveSelectedProfileID() {
        guard let selectedProfileID else { return }
        userDefaults.set(selectedProfileID.uuidString, forKey: selectedProfileKey)
    }

    /// Guarantees there is always at least one profile and a valid selection.
    /// Called once at launch so `activeProfile` can stay a pure read.
    func ensureDefaultProfile() {
        if profiles.isEmpty {
            profiles = [ReaderProfile()]
            saveProfiles()
        }

        let hasValidSelection = selectedProfileID.map { id in profiles.contains { $0.id == id } } ?? false
        if !hasValidSelection {
            selectedProfileID = profiles[0].id
            saveSelectedProfileID()
        }
    }

    var activeProfile: ReaderProfile {
        if let selectedProfileID, let match = profiles.first(where: { $0.id == selectedProfileID }) {
            return match
        }
        return profiles[0]
    }

    private var activeProfileID: UUID {
        activeProfile.id
    }

    func selectProfile(_ profileID: UUID) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        selectedProfileID = profileID
        saveSelectedProfileID()
    }

    @discardableResult
    func addProfile(name: String, avatarSymbol: String, colorName: String) throws -> ReaderProfile {
        let profile = try ReaderProfile(
            name: Self.sanitizedProfileName(name),
            avatarSymbol: avatarSymbol,
            colorName: colorName
        )
        guard persistSyncRecords(syncRecords(for: profile)) else {
            throw BookStoreError.syncOutboxUnavailable
        }
        profiles.append(profile)
        selectedProfileID = profile.id
        saveProfiles()
        saveSelectedProfileID()
        return profile
    }

    func updateProfile(_ profileID: UUID, name: String, avatarSymbol: String, colorName: String) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        var updated = profiles[index]
        try updated.updateNickname(Self.sanitizedProfileName(name))
        updated.avatarSymbol = avatarSymbol
        updated.colorName = colorName
        updated.metadataModifiedAt = .now
        guard persistSyncRecords([syncProfileRecord(for: updated)]) else {
            throw BookStoreError.syncOutboxUnavailable
        }
        profiles[index] = updated
        saveProfiles()
    }

    func deleteProfile(_ profileID: UUID) {
        guard profiles.count > 1, profiles.contains(where: { $0.id == profileID }) else { return }

        let removedStates = readingStates.filter { $0.profileID == profileID }
        let removedBookmarks = bookmarks.filter { $0.profileID == profileID }
        let removedWords = savedWords.filter { $0.profileID == profileID }
        var operations: [LibraryOutboxOperation] = [
            .delete(LibraryRecordReference(
                recordType: "ReaderProfile",
                recordName: "profile-\(profileID.uuidString.lowercased())"
            )),
            .delete(LibraryRecordReference(
                recordType: "ReaderPreferences",
                recordName: "preferences-\(profileID.uuidString.lowercased())"
            )),
        ]
        operations += removedStates.compactMap(readingStateReference).map(LibraryOutboxOperation.delete)
        operations += removedBookmarks.map {
            .delete(LibraryRecordReference(
                recordType: "Bookmark",
                recordName: "bookmark-\($0.id.uuidString.lowercased())"
            ))
        }
        operations += removedWords.map {
            .delete(LibraryRecordReference(
                recordType: "SavedWord",
                recordName: "word-\($0.id.uuidString.lowercased())"
            ))
        }
        guard persistSyncOperations(operations) else { return }

        profiles.removeAll { $0.id == profileID }
        readingStates.removeAll { $0.profileID == profileID }
        bookmarks.removeAll { $0.profileID == profileID }
        savedWords.removeAll { $0.profileID == profileID }

        if selectedProfileID == profileID {
            selectedProfileID = profiles[0].id
            saveSelectedProfileID()
        }

        saveProfiles()
        saveReadingStates()
        saveBookmarks()
        saveSavedWords()
    }

    private static func sanitizedProfileName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func updateActiveProfile(_ update: (inout ReaderProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        var updated = profiles[index]
        update(&updated)
        updated.preferencesModifiedAt = .now
        guard persistSyncRecords([syncPreferencesRecord(for: updated)]) else { return }
        profiles[index] = updated
        saveProfiles()
    }

    var activeVoiceIdentifier: String {
        activeProfile.voiceIdentifier
    }

    var activeSpeechRate: Double {
        activeProfile.speechRate
    }

    var activeFontSize: Double {
        activeProfile.fontSize
    }

    var activeReaderTheme: ReaderTheme {
        ReaderTheme(rawValue: activeProfile.readerTheme) ?? .piperly
    }

    var activeVoiceIdentifierBinding: Binding<String> {
        Binding(
            get: { self.activeVoiceIdentifier },
            set: { value in self.updateActiveProfile { $0.voiceIdentifier = value } }
        )
    }

    var activeSpeechRateBinding: Binding<Double> {
        Binding(
            get: { self.activeSpeechRate },
            set: { value in self.updateActiveProfile { $0.speechRate = value } }
        )
    }

    var activeFontSizeBinding: Binding<Double> {
        Binding(
            get: { self.activeFontSize },
            set: { value in self.updateActiveProfile { $0.fontSize = value } }
        )
    }

    var activeReaderThemeBinding: Binding<String> {
        Binding(
            get: { self.activeProfile.readerTheme },
            set: { value in self.updateActiveProfile { $0.readerTheme = value } }
        )
    }

    func completeVoiceSetup() {
        updateActiveProfile { $0.hasCompletedVoiceSetup = true }
    }

    func loadReadingStates() {
        guard let saved = loadArray(ReadingState.self, forKey: readingStatesKey) else { return }
        readingStates = saved
    }

    func saveReadingStates() {
        persistArray(readingStates, forKey: readingStatesKey)
    }

    private func scheduleSaveBooks() {
        debouncedBooksSave?.cancel()
        debouncedBooksSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveBooks()
        }
    }

    private func scheduleSaveReadingStates() {
        debouncedReadingStatesSave?.cancel()
        debouncedReadingStatesSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveReadingStates()
        }
    }

    private func scheduleSaveWords() {
        debouncedWordsSave?.cancel()
        debouncedWordsSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveSavedWords()
        }
    }

    /// Cancels any pending debounced writes and persists immediately. Call when
    /// the reader is dismissed or the app moves to the background so recent
    /// reading position and tapped words are never lost.
    func flushPendingSaves() {
        debouncedBooksSave?.cancel()
        debouncedBooksSave = nil
        debouncedReadingStatesSave?.cancel()
        debouncedReadingStatesSave = nil
        debouncedWordsSave?.cancel()
        debouncedWordsSave = nil
        saveBooks()
        saveReadingStates()
        saveSavedWords()
        do {
            try librarySync.flush()
            syncOutboxStatus = .ready
        } catch {
            syncOutboxStatus = .blocked
        }
    }

    func importBook(from sourceURL: URL) async throws -> Book {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let snapshotsURL = importSnapshotsURL
        let snapshotURL = try await Task.detached(priority: .userInitiated) {
            try Self.snapshotSource(at: sourceURL, in: snapshotsURL)
        }.value
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        return try await importSnapshot(snapshotURL, originalName: sourceURL.lastPathComponent)
    }

    private func importSnapshot(_ snapshotURL: URL, originalName: String) async throws -> Book {
        let contentIdentity = try await Task.detached(priority: .userInitiated) {
            try Self.contentIdentity(for: snapshotURL)
        }.value

        if let importTask = importsByContentIdentity[contentIdentity] {
            return try await importTask.value
        }

        let importTask = Task {
            try await finishImport(
                snapshotURL,
                originalName: originalName,
                contentIdentity: contentIdentity
            )
        }
        importsByContentIdentity[contentIdentity] = importTask

        do {
            let book = try await importTask.value
            importsByContentIdentity[contentIdentity] = nil
            return book
        } catch {
            importsByContentIdentity[contentIdentity] = nil
            throw error
        }
    }

    private func finishImport(
        _ snapshotURL: URL,
        originalName: String,
        contentIdentity: String
    ) async throws -> Book {
        let storedFileName = Self.storageFileName(for: contentIdentity)
        let destURL = documentsURL.appendingPathComponent(storedFileName)

        if let existingBook = books.first(where: { $0.contentIdentity == contentIdentity }) {
            if FileManager.default.fileExists(atPath: destURL.path) {
                let filesMatch = try await Task.detached(priority: .userInitiated) {
                    try Self.filesHaveEqualBytes(snapshotURL, destURL)
                }.value
                guard filesMatch else { throw BookStoreError.contentIdentityCollision }
            } else {
                _ = try await openPublication(at: snapshotURL)
                try await publishSnapshot(snapshotURL, to: destURL)
            }
            return existingBook
        }

        guard let (title, author, coverName) = try? await parseMetadataAndCover(from: snapshotURL) else {
            throw BookStoreError.unreadableBook
        }

        do {
            try await publishSnapshot(snapshotURL, to: destURL)
        } catch {
            if let coverName {
                try? FileManager.default.removeItem(at: coversURL.appendingPathComponent(coverName))
            }
            throw error
        }

        let book = Book(
            contentIdentity: contentIdentity,
            title: title ?? URL(fileURLWithPath: originalName).deletingPathExtension().lastPathComponent,
            author: author ?? "Unknown Author",
            fileName: storedFileName,
            coverImageName: coverName
        )

        guard persistSyncRecord(syncRecord(for: book)) else {
            try? FileManager.default.removeItem(at: destURL)
            if let coverName {
                try? FileManager.default.removeItem(at: coversURL.appendingPathComponent(coverName))
            }
            throw BookStoreError.syncOutboxUnavailable
        }

        books.append(book)
        saveBooks()
        return book
    }

    private func publishSnapshot(_ snapshotURL: URL, to destURL: URL) async throws {
        if FileManager.default.fileExists(atPath: destURL.path) {
            let filesMatch = try await Task.detached(priority: .userInitiated) {
                try Self.filesHaveEqualBytes(snapshotURL, destURL)
            }.value
            guard filesMatch else { throw BookStoreError.contentIdentityCollision }
            return
        }

        do {
            try FileManager.default.moveItem(at: snapshotURL, to: destURL)
        } catch {
            guard FileManager.default.fileExists(atPath: destURL.path) else { throw error }
            let filesMatch = try await Task.detached(priority: .userInitiated) {
                try Self.filesHaveEqualBytes(snapshotURL, destURL)
            }.value
            guard filesMatch else { throw BookStoreError.contentIdentityCollision }
        }
    }

    nonisolated private static func snapshotSource(at sourceURL: URL, in directoryURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let snapshotURL = directoryURL.appendingPathComponent("\(UUID().uuidString).epub")
        do {
            try FileManager.default.copyItem(at: sourceURL, to: snapshotURL)
            return snapshotURL
        } catch {
            try? FileManager.default.removeItem(at: snapshotURL)
            throw error
        }
    }

    nonisolated private static func clearStaleSnapshots(in directoryURL: URL) {
        guard let staleURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else { return }

        for staleURL in staleURLs {
            try? FileManager.default.removeItem(at: staleURL)
        }
    }

    nonisolated static func contentIdentity(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let bytes = try handle.read(upToCount: fileReadChunkSize), !bytes.isEmpty {
            hasher.update(data: bytes)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func storageFileName(for contentIdentity: String) -> String {
        "\(contentIdentity).epub"
    }

    nonisolated private static func filesHaveEqualBytes(_ firstURL: URL, _ secondURL: URL) throws -> Bool {
        let firstHandle = try FileHandle(forReadingFrom: firstURL)
        defer { try? firstHandle.close() }
        let secondHandle = try FileHandle(forReadingFrom: secondURL)
        defer { try? secondHandle.close() }

        while true {
            let firstBytes = try firstHandle.read(upToCount: fileReadChunkSize)
            let secondBytes = try secondHandle.read(upToCount: fileReadChunkSize)
            guard firstBytes == secondBytes else { return false }
            guard let firstBytes, !firstBytes.isEmpty else { return true }
        }
    }

    func bookURL(for book: Book) -> URL {
        documentsURL.appendingPathComponent(book.fileName)
    }

    func coverImage(for book: Book) -> UIImage? {
        guard let name = book.coverImageName else { return nil }
        let url = coversURL.appendingPathComponent(name)
        return UIImage(contentsOfFile: url.path)
    }

    func updateProgress(for bookID: UUID, progression: Double) {
        let profileID = activeProfileID
        let state: ReadingState
        if let index = readingStates.firstIndex(where: { $0.bookID == bookID && $0.profileID == profileID }) {
            var updated = readingStates[index]
            updated.lastReadProgression = progression
            updated.updatedAt = .now
            state = updated
            guard persistSyncRecord(syncRecord(for: state)) else { return }
            readingStates[index] = updated
        } else {
            state = ReadingState(
                profileID: profileID,
                bookID: bookID,
                lastReadProgression: progression
            )
            guard persistSyncRecord(syncRecord(for: state)) else { return }
            readingStates.append(state)
        }
        scheduleSaveReadingStates()
    }

    func updateLocator(for bookID: UUID, locatorJSON: String) {
        let profileID = activeProfileID
        let state: ReadingState
        if let index = readingStates.firstIndex(where: { $0.bookID == bookID && $0.profileID == profileID }) {
            var updated = readingStates[index]
            updated.lastReadLocatorJSON = locatorJSON
            updated.updatedAt = .now
            state = updated
            guard persistSyncRecord(syncRecord(for: state)) else { return }
            readingStates[index] = updated
        } else {
            state = ReadingState(
                profileID: profileID,
                bookID: bookID,
                lastReadLocatorJSON: locatorJSON
            )
            guard persistSyncRecord(syncRecord(for: state)) else { return }
            readingStates.append(state)
        }
        scheduleSaveReadingStates()
    }

    func readingState(for bookID: UUID) -> ReadingState? {
        let profileID = activeProfileID
        return readingStates.first { $0.bookID == bookID && $0.profileID == profileID }
    }

    // MARK: - Bookmarks

    func loadBookmarks() {
        guard let saved = loadArray(Bookmark.self, forKey: bookmarksKey) else { return }
        let needsProfileBackfill = saved.contains { $0.profileID == ProfileScopedDefaults.legacyProfileID }
        bookmarks = backfillProfileID(saved)
        if needsProfileBackfill { saveBookmarks() }
    }

    func saveBookmarks() {
        persistArray(bookmarks, forKey: bookmarksKey)
    }

    func addBookmark(for bookID: UUID, locatorJSON: String, title: String?, progression: Double, sticker: BookmarkSticker) {
        let bookmark = Bookmark(
            profileID: activeProfileID,
            bookID: bookID,
            locatorJSON: locatorJSON,
            title: title,
            progression: progression,
            sticker: sticker
        )
        guard persistSyncRecord(syncRecord(for: bookmark)) else { return }
        bookmarks.append(bookmark)
        saveBookmarks()
    }

    func removeBookmark(_ id: UUID) {
        guard bookmarks.contains(where: { $0.id == id }) else { return }
        let reference = LibraryRecordReference(
            recordType: "Bookmark",
            recordName: "bookmark-\(id.uuidString.lowercased())"
        )
        guard persistSyncOperations([.delete(reference)]) else { return }
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
    }

    func bookmarks(for bookID: UUID) -> [Bookmark] {
        let profileID = activeProfileID
        return bookmarks.filter { $0.bookID == bookID && $0.profileID == profileID }
            .sorted { $0.progression < $1.progression }
    }

    func isBookmarked(bookID: UUID, progression: Double) -> Bool {
        let profileID = activeProfileID
        return bookmarks.contains {
            $0.bookID == bookID && $0.profileID == profileID && abs($0.progression - progression) < 0.001
        }
    }

    func findBookmark(bookID: UUID, progression: Double) -> Bookmark? {
        let profileID = activeProfileID
        return bookmarks.first {
            $0.bookID == bookID && $0.profileID == profileID && abs($0.progression - progression) < 0.001
        }
    }

    // MARK: - Saved Words

    func loadSavedWords() {
        guard let saved = loadArray(SavedWord.self, forKey: savedWordsKey) else { return }
        let needsProfileBackfill = saved.contains { $0.profileID == ProfileScopedDefaults.legacyProfileID }
        savedWords = backfillProfileID(saved)
        if needsProfileBackfill { saveSavedWords() }
    }

    func saveSavedWords() {
        persistArray(savedWords, forKey: savedWordsKey)
    }

    @discardableResult
    func saveWordReturningIsNew(_ word: String, bookID: UUID, bookTitle: String) -> Bool {
        let canonical = word.lowercased()
        let profileID = activeProfileID
        if let index = savedWords.firstIndex(where: { $0.word == canonical && $0.bookID == bookID && $0.profileID == profileID }) {
            var updated = savedWords[index]
            updated.tapCount += 1
            updated.lastTappedAt = .now
            updated.modifiedAt = .now
            guard persistSyncRecord(syncRecord(for: updated)) else { return false }
            savedWords[index] = updated
            scheduleSaveWords()
            return false
        } else {
            let saved = SavedWord(
                profileID: profileID,
                word: canonical,
                displayWord: word,
                bookID: bookID,
                bookTitle: bookTitle
            )
            guard persistSyncRecord(syncRecord(for: saved)) else { return false }
            savedWords.append(saved)
            scheduleSaveWords()
            return true
        }
    }

    func removeWord(_ id: UUID) {
        guard savedWords.contains(where: { $0.id == id }) else { return }
        let reference = LibraryRecordReference(
            recordType: "SavedWord",
            recordName: "word-\(id.uuidString.lowercased())"
        )
        guard persistSyncOperations([.delete(reference)]) else { return }
        savedWords.removeAll { $0.id == id }
        saveSavedWords()
    }

    func words(for bookID: UUID) -> [SavedWord] {
        let profileID = activeProfileID
        return savedWords.filter { $0.bookID == bookID && $0.profileID == profileID }
            .sorted { $0.lastTappedAt > $1.lastTappedAt }
    }

    var wordsForActiveProfile: [SavedWord] {
        let profileID = activeProfileID
        return savedWords.filter { $0.profileID == profileID }
    }

    // MARK: - Samples

    func importSampleBooksIfNeeded() async {
        let hasImportedSamples = userDefaults.bool(forKey: "piperly_samples_imported")
        guard !hasImportedSamples else { return }

        let sampleFiles = Bundle.main.urls(forResourcesWithExtension: "epub", subdirectory: nil) ?? []
        for url in sampleFiles {
            _ = try? await importBundledBook(from: url)
        }

        userDefaults.set(true, forKey: "piperly_samples_imported")
    }

    private func importBundledBook(from bundleURL: URL) async throws -> Book {
        try await importBook(from: bundleURL)
    }

    func deleteBook(_ book: Book) {
        let removedStates = readingStates.filter { $0.bookID == book.id }
        let removedBookmarks = bookmarks.filter { $0.bookID == book.id }
        let removedWords = savedWords.filter { $0.bookID == book.id }
        var operations: [LibraryOutboxOperation] = [
            .delete(LibraryRecordReference(recordType: "Book", recordName: book.contentIdentity.lowercased())),
        ]
        operations += removedStates.map {
            .delete(LibraryRecordReference(
                recordType: "ReadingState",
                recordName: "reading-\($0.profileID.uuidString.lowercased())-\(book.contentIdentity.lowercased())"
            ))
        }
        operations += removedBookmarks.map {
            .delete(LibraryRecordReference(
                recordType: "Bookmark",
                recordName: "bookmark-\($0.id.uuidString.lowercased())"
            ))
        }
        operations += removedWords.map {
            .delete(LibraryRecordReference(
                recordType: "SavedWord",
                recordName: "word-\($0.id.uuidString.lowercased())"
            ))
        }
        guard persistSyncOperations(operations) else { return }
        let url = bookURL(for: book)
        try? FileManager.default.removeItem(at: url)
        if let coverName = book.coverImageName {
            try? FileManager.default.removeItem(at: coversURL.appendingPathComponent(coverName))
        }
        books.removeAll { $0.id == book.id }
        readingStates.removeAll { $0.bookID == book.id }
        bookmarks.removeAll { $0.bookID == book.id }
        savedWords.removeAll { $0.bookID == book.id }
        saveBooks()
        saveReadingStates()
        saveBookmarks()
        saveSavedWords()
    }

    func openPublication(at url: URL) async throws -> Publication {
        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let parser = DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: assetRetriever,
            pdfFactory: DefaultPDFDocumentFactory()
        )

        guard let fileURL = FileURL(url: url) else {
            throw BookStoreError.invalidURL
        }

        let asset = try await assetRetriever.retrieve(url: fileURL).get()
        let builder = try await parser.parse(asset: asset, warnings: nil).get()
        return builder.build()
    }

    private func parseMetadataAndCover(from url: URL) async throws -> (title: String?, author: String?, coverName: String?) {
        let publication = try await openPublication(at: url)
        let title = publication.metadata.title
        let author = publication.metadata.authors.first?.name
        let coverName = await extractCover(from: publication)
        return (title, author, coverName)
    }

    private func extractCover(from publication: Publication) async -> String? {
        nonisolated(unsafe) let unsafePub = publication
        guard let image = try? await unsafePub.cover().get(),
              let jpegData = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        let name = UUID().uuidString + ".jpg"
        let url = coversURL.appendingPathComponent(name)
        try? jpegData.write(to: url)
        return name
    }

    /// Legacy books decoded with an empty `contentIdentity` (persisted before
    /// stable identity existed). Hash the on-disk file, adopt the real identity,
    /// and migrate the file to the deterministic `<hash>.epub` name so dedupe
    /// and asset sync work. Legacy files still resolve via their old `fileName`
    /// until migrated, so nothing breaks before this runs.
    func backfillContentIdentities() async {
        var changed = false
        for i in books.indices where books[i].contentIdentity.isEmpty {
            let currentURL = bookURL(for: books[i])
            guard FileManager.default.fileExists(atPath: currentURL.path),
                  let identity = try? await Task.detached(priority: .utility, operation: {
                      try Self.contentIdentity(for: currentURL)
                  }).value else { continue }

            let storedName = Self.storageFileName(for: identity)
            let destURL = documentsURL.appendingPathComponent(storedName)
            if currentURL.path != destURL.path {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    // Deterministic name already present (same bytes): drop the
                    // duplicate legacy file rather than clobber the canonical one.
                    try? FileManager.default.removeItem(at: currentURL)
                } else {
                    try? FileManager.default.moveItem(at: currentURL, to: destURL)
                }
            }
            books[i] = Book(
                id: books[i].id,
                contentIdentity: identity,
                title: books[i].title,
                author: books[i].author,
                fileName: storedName,
                coverImageName: books[i].coverImageName
            )
            changed = true
        }
        if changed { saveBooks() }
    }

    func backfillCovers() async {
        var changed = false
        for i in books.indices where books[i].coverImageName == nil {
            let url = bookURL(for: books[i])
            guard FileManager.default.fileExists(atPath: url.path),
                  let publication = try? await openPublication(at: url),
                  let coverName = await extractCover(from: publication) else { continue }
            var updated = books[i]
            updated.coverImageName = coverName
            updated.modifiedAt = .now
            guard persistSyncRecord(syncRecord(for: updated)) else {
                try? FileManager.default.removeItem(at: coversURL.appendingPathComponent(coverName))
                continue
            }
            books[i] = updated
            changed = true
        }
        if changed { saveBooks() }
    }

    // MARK: - Library Sync

    func librarySnapshotRecords() -> [LibraryRecord] {
        books.map(syncRecord)
            + profiles.flatMap(syncRecords)
            + readingStates.compactMap(syncRecord)
            + bookmarks.compactMap(syncRecord)
            + savedWords.compactMap(syncRecord)
    }

    private func syncRecord(for book: Book) -> LibraryRecord {
        .book(SyncedBook(
            id: book.id,
            contentIdentity: book.contentIdentity,
            title: book.title,
            author: book.author,
            originalExtension: URL(fileURLWithPath: book.fileName).pathExtension,
            hasCover: book.coverImageName != nil,
            modifiedAt: book.modifiedAt
        ))
    }

    private func syncRecords(for profile: ReaderProfile) -> [LibraryRecord] {
        [syncProfileRecord(for: profile), syncPreferencesRecord(for: profile)]
    }

    private func syncProfileRecord(for profile: ReaderProfile) -> LibraryRecord {
        .readerProfile(SyncedReaderProfile(
            id: profile.id,
            nickname: profile.name,
            avatarSymbol: profile.avatarSymbol,
            colorName: profile.colorName,
            createdAt: profile.createdAt,
            modifiedAt: profile.metadataModifiedAt
        ))
    }

    private func syncPreferencesRecord(for profile: ReaderProfile) -> LibraryRecord {
        .readerPreferences(SyncedReaderPreferences(
            profileID: profile.id,
            voiceIdentifier: profile.voiceIdentifier,
            speechRate: profile.speechRate,
            fontSize: profile.fontSize,
            readerTheme: profile.readerTheme,
            hasCompletedVoiceSetup: profile.hasCompletedVoiceSetup,
            modifiedAt: profile.preferencesModifiedAt
        ))
    }

    private func syncRecord(for state: ReadingState) -> LibraryRecord? {
        guard let bookIdentity = books.first(where: { $0.id == state.bookID })?.contentIdentity else { return nil }
        return .readingState(SyncedReadingState(
            profileID: state.profileID,
            bookIdentity: bookIdentity,
            progression: state.lastReadProgression,
            locatorJSON: state.lastReadLocatorJSON,
            modifiedAt: state.updatedAt
        ))
    }

    private func syncRecord(for bookmark: Bookmark) -> LibraryRecord? {
        guard let bookIdentity = books.first(where: { $0.id == bookmark.bookID })?.contentIdentity else { return nil }
        return .bookmark(SyncedBookmark(
            id: bookmark.id,
            profileID: bookmark.profileID,
            bookIdentity: bookIdentity,
            locatorJSON: bookmark.locatorJSON,
            title: bookmark.title,
            progression: bookmark.progression,
            sticker: bookmark.sticker.rawValue,
            createdAt: bookmark.createdAt,
            modifiedAt: bookmark.modifiedAt
        ))
    }

    private func syncRecord(for word: SavedWord) -> LibraryRecord? {
        guard let bookIdentity = books.first(where: { $0.id == word.bookID })?.contentIdentity else { return nil }
        return .savedWord(SyncedSavedWord(
            id: word.id,
            profileID: word.profileID,
            bookIdentity: bookIdentity,
            canonicalWord: word.word,
            displayWord: word.displayWord,
            bookTitle: word.bookTitle,
            tapCount: word.tapCount,
            savedAt: word.savedAt,
            lastTappedAt: word.lastTappedAt,
            modifiedAt: word.modifiedAt
        ))
    }

    private func readingStateReference(for state: ReadingState) -> LibraryRecordReference? {
        guard let identity = books.first(where: { $0.id == state.bookID })?.contentIdentity else { return nil }
        return LibraryRecordReference(
            recordType: "ReadingState",
            recordName: "reading-\(state.profileID.uuidString.lowercased())-\(identity.lowercased())"
        )
    }

    private func persistSyncRecord(_ record: LibraryRecord?) -> Bool {
        guard let record else {
            syncOutboxStatus = .blocked
            return false
        }
        return persistSyncRecords([record])
    }

    private func persistSyncRecords(_ records: [LibraryRecord]) -> Bool {
        persistSyncOperations(records.map(LibraryOutboxOperation.save))
    }

    private func persistSyncOperations(_ operations: [LibraryOutboxOperation]) -> Bool {
        do {
            try librarySync.enqueue(operations)
            syncOutboxStatus = .ready
            return true
        } catch {
            syncOutboxStatus = .blocked
            return false
        }
    }

    /// Applies a complete fetched batch without using the local mutation
    /// methods, which prevents downloaded records from being queued again.
    func applyRemoteChanges(_ changes: [LibraryRemoteChange]) -> RemoteApplicationResult {
        let deletions = changes.compactMap { change -> LibraryRecordReference? in
            guard case .delete(let reference) = change else { return nil }
            return reference
        }
        let unresolvedDeletions = deletions.filter { !applyRemoteDelete($0) }

        let records = changes.compactMap { change -> LibraryRecord? in
            guard case .save(let record) = change else { return nil }
            return record
        }.sorted { $0.remoteApplicationOrder < $1.remoteApplicationOrder }
        let unresolved = records.filter { !applyRemoteSave($0) }

        saveBooks()
        saveProfiles()
        saveReadingStates()
        saveBookmarks()
        saveSavedWords()
        if !profiles.isEmpty { ensureDefaultProfile() }
        return RemoteApplicationResult(
            unresolvedRecords: unresolved,
            unresolvedDeletions: unresolvedDeletions
        )
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func applyRemoteSave(_ record: LibraryRecord) -> Bool {
        switch record {
        case .book(let remote):
            guard let existing = books.first(where: { $0.contentIdentity == remote.contentIdentity }) else {
                books.append(Book(
                    id: remote.id,
                    contentIdentity: remote.contentIdentity,
                    title: remote.title,
                    author: remote.author,
                    fileName: Self.storageFileName(for: remote.contentIdentity),
                    modifiedAt: remote.modifiedAt
                ))
                return true
            }
            let local = SyncedBook(
                id: existing.id,
                contentIdentity: existing.contentIdentity,
                title: existing.title,
                author: existing.author,
                originalExtension: URL(fileURLWithPath: existing.fileName).pathExtension,
                hasCover: existing.coverImageName != nil,
                modifiedAt: existing.modifiedAt
            )
            guard case .book(let merged) = LibraryConflictResolver.merge(local: .book(local), remote: record),
                  let index = books.firstIndex(where: { $0.id == existing.id }) else { return true }
            books[index] = Book(
                id: existing.id,
                contentIdentity: merged.contentIdentity,
                title: merged.title,
                author: merged.author,
                fileName: existing.fileName,
                coverImageName: existing.coverImageName,
                modifiedAt: merged.modifiedAt
            )
            return true
        case .readerProfile(let remote):
            if let index = profiles.firstIndex(where: { $0.id == remote.id }) {
                guard remote.modifiedAt >= profiles[index].metadataModifiedAt else { return true }
                let existing = profiles[index]
                guard let merged = try? ReaderProfile(
                    id: remote.id,
                    name: remote.nickname,
                    avatarSymbol: remote.avatarSymbol,
                    colorName: remote.colorName,
                    createdAt: remote.createdAt,
                    voiceIdentifier: existing.voiceIdentifier,
                    speechRate: existing.speechRate,
                    fontSize: existing.fontSize,
                    readerTheme: existing.readerTheme,
                    hasCompletedVoiceSetup: existing.hasCompletedVoiceSetup,
                    metadataModifiedAt: remote.modifiedAt,
                    preferencesModifiedAt: existing.preferencesModifiedAt
                ) else { return true }
                profiles[index] = merged
            } else {
                guard let profile = try? ReaderProfile(
                    id: remote.id,
                    name: remote.nickname,
                    avatarSymbol: remote.avatarSymbol,
                    colorName: remote.colorName,
                    createdAt: remote.createdAt,
                    metadataModifiedAt: remote.modifiedAt,
                    preferencesModifiedAt: .distantPast
                ) else { return true }
                profiles.append(profile)
            }
            return true
        case .readerPreferences(let remote):
            guard let index = profiles.firstIndex(where: { $0.id == remote.profileID }) else { return false }
            guard remote.modifiedAt >= profiles[index].preferencesModifiedAt else { return true }
            profiles[index].voiceIdentifier = remote.voiceIdentifier
            profiles[index].speechRate = remote.speechRate
            profiles[index].fontSize = remote.fontSize
            profiles[index].readerTheme = remote.readerTheme
            profiles[index].hasCompletedVoiceSetup = remote.hasCompletedVoiceSetup
            profiles[index].preferencesModifiedAt = remote.modifiedAt
            return true
        case .readingState(let remote):
            guard profiles.contains(where: { $0.id == remote.profileID }),
                  let bookID = books.first(where: { $0.contentIdentity == remote.bookIdentity })?.id else { return false }
            if let index = readingStates.firstIndex(where: { $0.profileID == remote.profileID && $0.bookID == bookID }) {
                let current = readingStates[index]
                let local = SyncedReadingState(
                    profileID: remote.profileID,
                    bookIdentity: remote.bookIdentity,
                    progression: current.lastReadProgression,
                    locatorJSON: current.lastReadLocatorJSON,
                    modifiedAt: current.updatedAt
                )
                let merged = LibraryConflictResolver.merge(local: local, remote: remote)
                readingStates[index].lastReadProgression = merged.progression
                readingStates[index].lastReadLocatorJSON = merged.locatorJSON
                readingStates[index].updatedAt = merged.modifiedAt
            } else {
                readingStates.append(ReadingState(
                    profileID: remote.profileID,
                    bookID: bookID,
                    lastReadProgression: remote.progression,
                    lastReadLocatorJSON: remote.locatorJSON,
                    updatedAt: remote.modifiedAt
                ))
            }
            return true
        case .bookmark(let remote):
            guard profiles.contains(where: { $0.id == remote.profileID }),
                  let bookID = books.first(where: { $0.contentIdentity == remote.bookIdentity })?.id else { return false }
            guard let sticker = BookmarkSticker(rawValue: remote.sticker) else { return true }
            let value = Bookmark(
                id: remote.id,
                profileID: remote.profileID,
                bookID: bookID,
                locatorJSON: remote.locatorJSON,
                title: remote.title,
                progression: remote.progression,
                sticker: sticker,
                createdAt: remote.createdAt,
                modifiedAt: remote.modifiedAt
            )
            if let index = bookmarks.firstIndex(where: { $0.id == remote.id }) {
                if remote.modifiedAt >= bookmarks[index].modifiedAt { bookmarks[index] = value }
            } else {
                bookmarks.append(value)
            }
            return true
        case .savedWord(let remote):
            guard profiles.contains(where: { $0.id == remote.profileID }),
                  let bookID = books.first(where: { $0.contentIdentity == remote.bookIdentity })?.id else { return false }
            let value = SavedWord(
                id: remote.id,
                profileID: remote.profileID,
                word: remote.canonicalWord,
                displayWord: remote.displayWord,
                bookID: bookID,
                bookTitle: remote.bookTitle,
                tapCount: remote.tapCount,
                savedAt: remote.savedAt,
                lastTappedAt: remote.lastTappedAt,
                modifiedAt: remote.modifiedAt
            )
            if let index = savedWords.firstIndex(where: { $0.id == remote.id }) {
                let local = syncedSavedWord(savedWords[index], bookIdentity: remote.bookIdentity)
                guard case .savedWord(let merged) = LibraryConflictResolver.merge(
                    local: .savedWord(local),
                    remote: record
                ) else { return true }
                savedWords[index] = SavedWord(
                    id: merged.id,
                    profileID: merged.profileID,
                    word: merged.canonicalWord,
                    displayWord: merged.displayWord,
                    bookID: bookID,
                    bookTitle: merged.bookTitle,
                    tapCount: merged.tapCount,
                    savedAt: merged.savedAt,
                    lastTappedAt: merged.lastTappedAt,
                    modifiedAt: merged.modifiedAt
                )
            } else {
                savedWords.append(value)
            }
            return true
        }
    }

    private func syncedSavedWord(_ word: SavedWord, bookIdentity: String) -> SyncedSavedWord {
        SyncedSavedWord(
            id: word.id,
            profileID: word.profileID,
            bookIdentity: bookIdentity,
            canonicalWord: word.word,
            displayWord: word.displayWord,
            bookTitle: word.bookTitle,
            tapCount: word.tapCount,
            savedAt: word.savedAt,
            lastTappedAt: word.lastTappedAt,
            modifiedAt: word.modifiedAt
        )
    }

    private func applyRemoteDelete(_ reference: LibraryRecordReference) -> Bool {
        switch reference.recordType {
        case "Book":
            guard let book = books.first(where: { $0.contentIdentity == reference.recordName }) else { return true }
            try? FileManager.default.removeItem(at: bookURL(for: book))
            if let coverImageName = book.coverImageName {
                try? FileManager.default.removeItem(at: coversURL.appendingPathComponent(coverImageName))
            }
            books.removeAll { $0.id == book.id }
            readingStates.removeAll { $0.bookID == book.id }
            bookmarks.removeAll { $0.bookID == book.id }
            savedWords.removeAll { $0.bookID == book.id }
            return true
        case "ReaderProfile":
            guard let id = uuid(from: reference.recordName, prefix: "profile-") else { return true }
            profiles.removeAll { $0.id == id }
            readingStates.removeAll { $0.profileID == id }
            bookmarks.removeAll { $0.profileID == id }
            savedWords.removeAll { $0.profileID == id }
            // Deleting the last profile leaves an empty library; recreate a default.
            // Keyed on "no profiles exist," not a stale count, so a retry after a
            // failed replacement-enqueue is idempotent and never spawns duplicates.
            // The deletion itself is resolved regardless: a failed replacement
            // enqueue must not re-run the delete, or each retry churns another profile.
            if profiles.isEmpty {
                let replacement = ReaderProfile()
                _ = persistSyncRecords(syncRecords(for: replacement))
                profiles.append(replacement)
                selectedProfileID = replacement.id
            }
            return true
        case "ReadingState":
            readingStates.removeAll { readingStateReference(for: $0) == reference }
            return true
        case "Bookmark":
            if let id = uuid(from: reference.recordName, prefix: "bookmark-") {
                bookmarks.removeAll { $0.id == id }
            }
            return true
        case "SavedWord":
            if let id = uuid(from: reference.recordName, prefix: "word-") {
                savedWords.removeAll { $0.id == id }
            }
            return true
        case "ReaderPreferences":
            return true
        default:
            return true
        }
    }

    private func uuid(from recordName: String, prefix: String) -> UUID? {
        guard recordName.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(recordName.dropFirst(prefix.count)))
    }
}

enum BookStoreError: Error {
    case invalidURL
    case unreadableBook
    case contentIdentityCollision
    case syncOutboxUnavailable
}

/// Decodes to `nil` instead of throwing, so a bad element in an array doesn't
/// fail the whole decode. Used for tolerant persisted-store loading.
private struct FailableCodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}
