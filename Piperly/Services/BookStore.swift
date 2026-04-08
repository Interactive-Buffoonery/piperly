import Foundation
import ReadiumShared
import ReadiumStreamer

@MainActor
class BookStore: ObservableObject {
    @Published var books: [Book] = []

    private let documentsURL: URL
    private let booksKey = "piperly_books"

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.documentsURL = docs.appendingPathComponent("Books", isDirectory: true)

        try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        loadBooks()
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
            saveBooks()
        }
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
