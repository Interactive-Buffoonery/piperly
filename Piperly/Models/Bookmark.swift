import Foundation
import SwiftUI

struct Bookmark: Identifiable, Codable, Hashable {
    let id: UUID
    let bookID: UUID
    let locatorJSON: String
    let title: String?
    let progression: Double
    let sticker: BookmarkSticker
    let createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        locatorJSON: String,
        title: String?,
        progression: Double,
        sticker: BookmarkSticker,
        createdAt: Date = .now
    ) {
        self.id = id
        self.bookID = bookID
        self.locatorJSON = locatorJSON
        self.title = title
        self.progression = progression
        self.sticker = sticker
        self.createdAt = createdAt
    }
}

enum BookmarkSticker: String, Codable, CaseIterable, Hashable {
    case star
    case heart
    case lightbulb
    case question
    case bookmark

    var symbol: String {
        switch self {
        case .star: "star.fill"
        case .heart: "heart.fill"
        case .lightbulb: "lightbulb.fill"
        case .question: "questionmark.circle.fill"
        case .bookmark: "bookmark.fill"
        }
    }

    var label: String {
        switch self {
        case .star: "Favorite"
        case .heart: "Love it"
        case .lightbulb: "Learned"
        case .question: "Question"
        case .bookmark: "Save"
        }
    }

    var color: Color {
        switch self {
        case .star: Piperly.Colors.warning
        case .heart: Piperly.Colors.error
        case .lightbulb: Piperly.Colors.success
        case .question: Piperly.Colors.info
        case .bookmark: Piperly.Colors.accent
        }
    }
}
