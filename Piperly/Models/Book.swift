import Foundation

struct Book: Identifiable, Codable {
    let id: UUID
    let title: String
    let author: String
    let fileName: String
    var coverImageName: String?
    var lastReadProgression: Double
    var lastReadLocatorJSON: String?

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        fileName: String,
        coverImageName: String? = nil,
        lastReadProgression: Double = 0.0,
        lastReadLocatorJSON: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.fileName = fileName
        self.coverImageName = coverImageName
        self.lastReadProgression = lastReadProgression
        self.lastReadLocatorJSON = lastReadLocatorJSON
    }
}
