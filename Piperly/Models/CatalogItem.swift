import Foundation

struct CatalogItem: Identifiable, Sendable {
    let id: String
    let title: String
    let author: String?
    let description: String?
    let coverURL: URL?
    let acquisitionURL: URL?
    let mediaType: String?
}

struct CatalogNavLink: Identifiable, Sendable {
    let id: String
    let title: String
    let href: String
}
