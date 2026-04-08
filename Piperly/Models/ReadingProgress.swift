import Foundation

struct ReadingProgress: Codable {
    let bookID: UUID
    var progression: Double
    var lastOpened: Date

    init(bookID: UUID, progression: Double = 0.0, lastOpened: Date = .now) {
        self.bookID = bookID
        self.progression = progression
        self.lastOpened = lastOpened
    }
}
