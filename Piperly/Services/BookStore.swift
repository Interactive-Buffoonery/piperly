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

@MainActor
class BookStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var profiles: [ReaderProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var readingStates: [ReadingState] = []
    @Published var bookmarks: [Bookmark] = []
    @Published var savedWords: [SavedWord] = []

    private let documentsURL: URL
    private let coversURL: URL
    private let importSnapshotsURL: URL
    private let userDefaults: UserDefaults
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

    convenience init(userDefaults: UserDefaults = .standard) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(
            documentsURL: docs.appendingPathComponent("Books", isDirectory: true),
            coversURL: docs.appendingPathComponent("Covers", isDirectory: true),
            userDefaults: userDefaults
        )
    }

    init(documentsURL: URL, coversURL: URL, userDefaults: UserDefaults) {
        self.documentsURL = documentsURL
        self.coversURL = coversURL
        self.importSnapshotsURL = documentsURL.deletingLastPathComponent()
            .appendingPathComponent(".PiperlyImportSnapshots", isDirectory: true)
        self.userDefaults = userDefaults

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
        guard let data = userDefaults.data(forKey: booksKey),
              let saved = try? JSONDecoder().decode([Book].self, from: data) else {
            return
        }
        books = saved
    }

    func saveBooks() {
        if let data = try? JSONEncoder().encode(books) {
            userDefaults.set(data, forKey: booksKey)
        }
    }

    func loadProfiles() {
        guard let data = userDefaults.data(forKey: profilesKey),
              let saved = try? JSONDecoder().decode([ReaderProfile].self, from: data) else {
            return
        }
        profiles = saved
    }

    func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            userDefaults.set(data, forKey: profilesKey)
        }
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
        profiles.append(profile)
        selectedProfileID = profile.id
        saveProfiles()
        saveSelectedProfileID()
        return profile
    }

    func updateProfile(_ profileID: UUID, name: String, avatarSymbol: String, colorName: String) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        try profiles[index].updateNickname(Self.sanitizedProfileName(name))
        profiles[index].avatarSymbol = avatarSymbol
        profiles[index].colorName = colorName
        saveProfiles()
    }

    func deleteProfile(_ profileID: UUID) {
        guard profiles.count > 1, profiles.contains(where: { $0.id == profileID }) else { return }

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
        update(&profiles[index])
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
        guard let data = userDefaults.data(forKey: readingStatesKey),
              let saved = try? JSONDecoder().decode([ReadingState].self, from: data) else {
            return
        }
        readingStates = saved
    }

    func saveReadingStates() {
        if let data = try? JSONEncoder().encode(readingStates) {
            userDefaults.set(data, forKey: readingStatesKey)
        }
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
        if let index = readingStates.firstIndex(where: { $0.bookID == bookID && $0.profileID == profileID }) {
            readingStates[index].lastReadProgression = progression
            readingStates[index].updatedAt = .now
        } else {
            readingStates.append(ReadingState(
                profileID: profileID,
                bookID: bookID,
                lastReadProgression: progression
            ))
        }
        scheduleSaveReadingStates()
    }

    func updateLocator(for bookID: UUID, locatorJSON: String) {
        let profileID = activeProfileID
        if let index = readingStates.firstIndex(where: { $0.bookID == bookID && $0.profileID == profileID }) {
            readingStates[index].lastReadLocatorJSON = locatorJSON
            readingStates[index].updatedAt = .now
        } else {
            readingStates.append(ReadingState(
                profileID: profileID,
                bookID: bookID,
                lastReadLocatorJSON: locatorJSON
            ))
        }
        scheduleSaveReadingStates()
    }

    func readingState(for bookID: UUID) -> ReadingState? {
        let profileID = activeProfileID
        return readingStates.first { $0.bookID == bookID && $0.profileID == profileID }
    }

    // MARK: - Bookmarks

    func loadBookmarks() {
        guard let data = userDefaults.data(forKey: bookmarksKey),
              let saved = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            return
        }
        bookmarks = saved
    }

    func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            userDefaults.set(data, forKey: bookmarksKey)
        }
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
        bookmarks.append(bookmark)
        saveBookmarks()
    }

    func removeBookmark(_ id: UUID) {
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
        guard let data = userDefaults.data(forKey: savedWordsKey),
              let saved = try? JSONDecoder().decode([SavedWord].self, from: data) else {
            return
        }
        savedWords = saved
    }

    func saveSavedWords() {
        if let data = try? JSONEncoder().encode(savedWords) {
            userDefaults.set(data, forKey: savedWordsKey)
        }
    }

    @discardableResult
    func saveWordReturningIsNew(_ word: String, bookID: UUID, bookTitle: String) -> Bool {
        let canonical = word.lowercased()
        let profileID = activeProfileID
        if let index = savedWords.firstIndex(where: { $0.word == canonical && $0.bookID == bookID && $0.profileID == profileID }) {
            savedWords[index].tapCount += 1
            savedWords[index].lastTappedAt = .now
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
            savedWords.append(saved)
            scheduleSaveWords()
            return true
        }
    }

    func removeWord(_ id: UUID) {
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
            books[i].coverImageName = coverName
            changed = true
        }
        if changed { saveBooks() }
    }
}

enum BookStoreError: Error {
    case invalidURL
    case unreadableBook
    case contentIdentityCollision
}
