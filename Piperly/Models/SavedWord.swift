import Foundation

struct SavedWord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let word: String
    let displayWord: String
    let bookID: UUID
    let bookTitle: String
    var tapCount: Int
    let savedAt: Date
    var lastTappedAt: Date

    init(
        id: UUID = UUID(),
        word: String,
        displayWord: String,
        bookID: UUID,
        bookTitle: String,
        tapCount: Int = 1,
        savedAt: Date = .now,
        lastTappedAt: Date = .now
    ) {
        self.id = id
        self.word = word
        self.displayWord = displayWord
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.tapCount = tapCount
        self.savedAt = savedAt
        self.lastTappedAt = lastTappedAt
    }
}
