import Foundation
import ReadiumShared
import ReadiumStreamer

@MainActor
class BookStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var bookmarks: [Bookmark] = []
    @Published var savedWords: [SavedWord] = []

    private let documentsURL: URL
    private let booksKey = "piperly_books"
    private let bookmarksKey = "piperly_bookmarks"
    private let savedWordsKey = "piperly_saved_words"
    private var debouncedBooksSave: Task<Void, Never>?
    private var debouncedWordsSave: Task<Void, Never>?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.documentsURL = docs.appendingPathComponent("Books", isDirectory: true)

        try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        loadBooks()
        loadBookmarks()
        loadSavedWords()
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

    private func scheduleSaveBooks() {
        debouncedBooksSave?.cancel()
        debouncedBooksSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveBooks()
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

    func importBook(from sourceURL: URL) async throws -> Book {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let fileName = sourceURL.lastPathComponent
        let destURL = documentsURL.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let (title, author) = await parseMetadata(from: destURL)

        let book = Book(
            title: title ?? fileName.replacingOccurrences(of: ".epub", with: ""),
            author: author ?? "Unknown Author",
            fileName: fileName
        )

        books.append(book)
        saveBooks()
        return book
    }

    func bookURL(for book: Book) -> URL {
        documentsURL.appendingPathComponent(book.fileName)
    }

    func updateProgress(for bookID: UUID, progression: Double) {
        if let index = books.firstIndex(where: { $0.id == bookID }) {
            books[index].lastReadProgression = progression
            scheduleSaveBooks()
        }
    }

    func updateLocator(for bookID: UUID, locatorJSON: String) {
        if let index = books.firstIndex(where: { $0.id == bookID }) {
            books[index].lastReadLocatorJSON = locatorJSON
            scheduleSaveBooks()
        }
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
        bookmarks.filter { $0.bookID == bookID }.sorted { $0.progression < $1.progression }
    }

    func isBookmarked(bookID: UUID, progression: Double) -> Bool {
        bookmarks.contains { $0.bookID == bookID && abs($0.progression - progression) < 0.001 }
    }

    func findBookmark(bookID: UUID, progression: Double) -> Bookmark? {
        bookmarks.first { $0.bookID == bookID && abs($0.progression - progression) < 0.001 }
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
        if let index = savedWords.firstIndex(where: { $0.word == canonical && $0.bookID == bookID }) {
            savedWords[index].tapCount += 1
            savedWords[index].lastTappedAt = .now
            scheduleSaveWords()
            return false
        } else {
            let saved = SavedWord(
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
        savedWords.filter { $0.bookID == bookID }
            .sorted { $0.lastTappedAt > $1.lastTappedAt }
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

        let (title, author) = await parseMetadata(from: destURL)

        let book = Book(
            title: title ?? fileName.replacingOccurrences(of: ".epub", with: ""),
            author: author ?? "Unknown Author",
            fileName: fileName
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
        books.removeAll { $0.id == book.id }
        saveBooks()
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

    private func parseMetadata(from url: URL) async -> (title: String?, author: String?) {
        guard let pub = try? await openPublication(at: url) else {
            return (nil, nil)
        }
        let title = pub.metadata.title
        let author = pub.metadata.authors.first?.name
        return (title, author)
    }
}

enum BookStoreError: Error {
    case invalidURL
}
