import Foundation
import ReadiumShared
import ReadiumOPDS

@MainActor
final class OPDSService: ObservableObject {
    @Published var isLoading = false
    @Published var catalogItems: [CatalogItem] = []
    @Published var navigationLinks: [CatalogNavLink] = []
    @Published var feedTitle: String = ""
    @Published var error: OPDSError?
    @Published var activeDownloads: [String: DownloadProgress] = [:]

    private var navStack: [(url: URL, title: String)] = []
    private var nextPageURL: URL?
    private var searchTemplate: String?
    private var cachedConfig: OPDSServerConfig?

    var canGoBack: Bool { navStack.count > 1 }
    var hasNextPage: Bool { nextPageURL != nil }
    var isConfigured: Bool { OPDSServerConfig.load() != nil }

    // MARK: - Feed Loading

    func loadCatalog() async {
        cachedConfig = OPDSServerConfig.load()
        guard let config = cachedConfig else {
            error = .notConfigured
            return
        }

        navStack = [(url: config.url, title: "Catalog")]
        await loadFeed(url: config.url)
    }

    func navigate(to href: String, title: String) async {
        guard let url = URL(string: href) else { return }
        navStack.append((url: url, title: title))
        await loadFeed(url: url)
    }

    func navigateBack() async {
        guard navStack.count > 1 else { return }
        navStack.removeLast()
        if let previous = navStack.last {
            await loadFeed(url: previous.url)
        }
    }

    func loadNextPage() async {
        guard let url = nextPageURL else { return }
        isLoading = true
        error = nil

        do {
            let feed = try await fetchAndParseFeed(url: url)
            let newItems = mapPublications(feed.publications)
            catalogItems.append(contentsOf: newItems)
            nextPageURL = feed.links.first { $0.rels.contains(.next) }
                .flatMap { URL(string: $0.href) }
        } catch {
            self.error = .connectionFailed
        }

        isLoading = false
    }

    // MARK: - Search

    func search(query: String) async {
        guard let template = searchTemplate,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return }

        let searchURLString = template.replacingOccurrences(of: "{searchTerms}", with: encoded)
        guard let url = URL(string: searchURLString) else { return }

        navStack.append((url: url, title: "Search: \(query)"))
        await loadFeed(url: url)
    }

    // MARK: - Download

    func downloadBook(_ item: CatalogItem, to bookStore: BookStore) async throws {
        guard let acquisitionURL = item.acquisitionURL,
              let url = URL(string: acquisitionURL.absoluteString)
        else {
            throw OPDSError.noAcquisitionLink
        }

        activeDownloads[item.id] = DownloadProgress(bytesReceived: 0, totalBytes: nil)

        do {
            let request = authenticatedRequest(for: url)
            let (data, _) = try await URLSession.shared.data(for: request)

            let totalBytes = Int64(data.count)
            activeDownloads[item.id]?.totalBytes = totalBytes
            activeDownloads[item.id]?.bytesReceived = totalBytes

            let tempDir = FileManager.default.temporaryDirectory
            let fileName = UUID().uuidString + ".epub"
            let tempURL = tempDir.appendingPathComponent(fileName)

            try data.write(to: tempURL)
            _ = try await bookStore.importBook(from: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            activeDownloads.removeValue(forKey: item.id)
        } catch {
            activeDownloads.removeValue(forKey: item.id)
            throw OPDSError.downloadFailed(error.localizedDescription)
        }
    }

    // MARK: - Connection Test

    func testConnection() async -> Bool {
        cachedConfig = OPDSServerConfig.load()
        guard let config = cachedConfig else { return false }

        do {
            _ = try await fetchAndParseFeed(url: config.url)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func loadFeed(url: URL) async {
        isLoading = true
        error = nil
        catalogItems = []
        navigationLinks = []

        do {
            let feed = try await fetchAndParseFeed(url: url)

            feedTitle = feed.metadata.title
            catalogItems = mapPublications(feed.publications)

            navigationLinks = feed.navigation.compactMap { link in
                guard let title = link.title else { return nil }
                return CatalogNavLink(id: link.href, title: title, href: link.href)
            }

            nextPageURL = feed.links.first { $0.rels.contains(.next) }
                .flatMap { URL(string: $0.href) }

            // Extract search template from feed links
            if let searchLink = feed.links.first(where: { $0.rels.contains(.search) }),
               let searchURL = URL(string: searchLink.href) {
                await fetchSearchTemplate(from: searchURL)
            }
        } catch {
            self.error = .connectionFailed
        }

        isLoading = false
    }

    private func fetchAndParseFeed(url: URL) async throws -> Feed {
        let request = authenticatedRequest(for: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let parseData = try? OPDS1Parser.parse(xmlData: data, url: url, response: response),
           let feed = parseData.feed {
            return feed
        }
        if let parseData = try? OPDS2Parser.parse(jsonData: data, url: url, response: response),
           let feed = parseData.feed {
            return feed
        }
        throw OPDSError.feedParsingFailed
    }

    private func fetchSearchTemplate(from url: URL) async {
        do {
            let request = authenticatedRequest(for: url)
            let (data, _) = try await URLSession.shared.data(for: request)

            // Parse OpenSearch XML for <Url template="...">
            if let xml = String(data: data, encoding: .utf8),
               let templateRange = xml.range(of: "template=\""),
               let endRange = xml[templateRange.upperBound...].range(of: "\"") {
                searchTemplate = String(xml[templateRange.upperBound..<endRange.lowerBound])
            }
        } catch {
            // Search not available -- not critical
        }
    }

    private func authenticatedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let authValue = (cachedConfig ?? OPDSServerConfig.load())?.authorizationHeaderValue() {
            request.setValue(authValue, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func mapPublications(_ publications: [Publication]) -> [CatalogItem] {
        publications.compactMap { pub in
            let title = pub.metadata.title ?? "Untitled"
            let author = pub.metadata.authors.first?.name

            // Cover: check images subcollection, then link rels
            let coverURL: URL? = {
                if let imageLinks = pub.manifest.subcollections["images"]?.first?.links,
                   let imageLink = imageLinks.first,
                   let url = URL(string: imageLink.href) {
                    return url
                }
                if let coverLink = pub.links.first(where: { $0.rels.contains(.opdsImage) || $0.rels.contains(.opdsImageThumbnail) }),
                   let url = URL(string: coverLink.href) {
                    return url
                }
                return nil
            }()

            // Acquisition link: prefer open-access, then generic
            let acquisitionLink: Link? = {
                pub.links.first { $0.rels.contains(.opdsAcquisitionOpenAccess) }
                ?? pub.links.first { $0.rels.contains(where: \.isOPDSAcquisition) }
            }()

            let acquisitionURL = acquisitionLink.flatMap { URL(string: $0.href) }

            return CatalogItem(
                id: pub.metadata.identifier ?? UUID().uuidString,
                title: title,
                author: author,
                description: pub.metadata.description,
                coverURL: coverURL,
                acquisitionURL: acquisitionURL,
                mediaType: acquisitionLink?.mediaType?.string
            )
        }
    }
}

// MARK: - Supporting Types

struct DownloadProgress: Sendable {
    var bytesReceived: Int64
    var totalBytes: Int64?

    var fraction: Double {
        guard let total = totalBytes, total > 0 else { return 0 }
        return Double(bytesReceived) / Double(total)
    }
}

enum OPDSError: Error {
    case notConfigured
    case connectionFailed
    case feedParsingFailed
    case downloadFailed(String)
    case noAcquisitionLink

    var friendlyMessage: String {
        switch self {
        case .notConfigured:
            return "No book server set up yet. Ask a grown-up to add one in Settings."
        case .connectionFailed:
            return "Can't reach the bookshelf -- ask a grown-up to check the internet!"
        case .feedParsingFailed:
            return "The bookshelf sent something unexpected."
        case .downloadFailed:
            return "This book couldn't be downloaded right now."
        case .noAcquisitionLink:
            return "This book can't be downloaded."
        }
    }
}
