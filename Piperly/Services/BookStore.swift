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
    private let booksKey = "piperly_books"
    private let profilesKey = "piperly_reader_profiles"
    private let selectedProfileKey = "piperly_selected_profile_id"
    private let readingStatesKey = "piperly_reading_states"
    private let bookmarksKey = "piperly_bookmarks"
    private let savedWordsKey = "piperly_saved_words"
    private var debouncedBooksSave: Task<Void, Never>?
    private var debouncedReadingStatesSave: Task<Void, Never>?
    private var debouncedWordsSave: Task<Void, Never>?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.documentsURL = docs.appendingPathComponent("Books", isDirectory: true)
        self.coversURL = docs.appendingPathComponent("Covers", isDirectory: true)

        try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: coversURL, withIntermediateDirectories: true)
        Self.excludeFromBackup(documentsURL)
        Self.excludeFromBackup(coversURL)
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
    private nonisolated static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    func loadBooks() {
        guard let data = UserDefaults.standard.data(forKey: booksKey),
              let saved = try? JSONDecoder().decode([Book].self, from: data) else {
            return
        }
        books = saved
    }

    func saveBooks() {
        if let data = try? JSONEncoder().encode(books) {
            UserDefaults.standard.set(data, forKey: booksKey)
        }
    }

    func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let saved = try? JSONDecoder().decode([ReaderProfile].self, from: data) else {
            return
        }
        profiles = saved
    }

    func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
    }

    func loadSelectedProfileID() {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedProfileKey),
              let id = UUID(uuidString: rawValue) else {
            return
        }
        selectedProfileID = id
    }

    func saveSelectedProfileID() {
        guard let selectedProfileID else { return }
        UserDefaults.standard.set(selectedProfileID.uuidString, forKey: selectedProfileKey)
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

    func loadReadingStates() {
        guard let data = UserDefaults.standard.data(forKey: readingStatesKey),
              let saved = try? JSONDecoder().decode([ReadingState].self, from: data) else {
            return
        }
        readingStates = saved
    }

    func saveReadingStates() {
        if let data = try? JSONEncoder().encode(readingStates) {
            UserDefaults.standard.set(data, forKey: readingStatesKey)
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

        let originalName = sourceURL.lastPathComponent
        let storedFileName = Self.uniqueFileName(for: originalName)
        let destURL = documentsURL.appendingPathComponent(storedFileName)

        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        guard let (title, author, coverName) = try? await parseMetadataAndCover(from: destURL) else {
            try? FileManager.default.removeItem(at: destURL)
            throw BookStoreError.unreadableBook
        }

        let book = Book(
            title: title ?? URL(fileURLWithPath: originalName).deletingPathExtension().lastPathComponent,
            author: author ?? "Unknown Author",
            fileName: storedFileName,
            coverImageName: coverName
        )

        books.append(book)
        saveBooks()
        return book
    }

    /// Builds a collision-free destination filename by prefixing a UUID, while
    /// preserving the original name (and extension) for readability.
    nonisolated static func uniqueFileName(for originalName: String) -> String {
        "\(UUID().uuidString)-\(originalName)"
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
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let saved = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            return
        }
        bookmarks = saved
    }

    func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
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
        guard let data = UserDefaults.standard.data(forKey: savedWordsKey),
              let saved = try? JSONDecoder().decode([SavedWord].self, from: data) else {
            return
        }
        savedWords = saved
    }

    func saveSavedWords() {
        if let data = try? JSONEncoder().encode(savedWords) {
            UserDefaults.standard.set(data, forKey: savedWordsKey)
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
        let hasImportedSamples = UserDefaults.standard.bool(forKey: "piperly_samples_imported")
        guard !hasImportedSamples else { return }

        let sampleFiles = Bundle.main.urls(forResourcesWithExtension: "epub", subdirectory: nil) ?? []
        for url in sampleFiles {
            _ = try? await importBundledBook(from: url)
        }

        UserDefaults.standard.set(true, forKey: "piperly_samples_imported")
    }

    private func importBundledBook(from bundleURL: URL) async throws -> Book {
        let fileName = bundleURL.lastPathComponent
        let destURL = documentsURL.appendingPathComponent(fileName)

        if !FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.copyItem(at: bundleURL, to: destURL)
        }

        let (title, author, coverName) = (try? await parseMetadataAndCover(from: destURL)) ?? (nil, nil, nil)

        let book = Book(
            title: title ?? URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent,
            author: author ?? "Unknown Author",
            fileName: fileName,
            coverImageName: coverName
        )

        if !books.contains(where: { $0.fileName == fileName }) {
            books.append(book)
            saveBooks()
        }
        return book
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
}
