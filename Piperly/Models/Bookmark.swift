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

/// Shared behavior for records scoped to a reader profile. Lets BookStore
/// rehome legacy records (persisted before profiles existed) onto the active
/// profile after a tolerant decode.
enum ProfileScopedDefaults {
    /// Sentinel assigned when a persisted record predates `profileID`.
    static let legacyProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

protocol ProfileScoped {
    var profileID: UUID { get }
    func withProfileID(_ id: UUID) -> Self
}

struct Bookmark: Identifiable, Codable, Hashable, ProfileScoped {
    let id: UUID
    let profileID: UUID
    let bookID: UUID
    let locatorJSON: String
    let title: String?
    let progression: Double
    let sticker: BookmarkSticker
    let createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        profileID: UUID,
        bookID: UUID,
        locatorJSON: String,
        title: String?,
        progression: Double,
        sticker: BookmarkSticker,
        createdAt: Date = .now,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.profileID = profileID
        self.bookID = bookID
        self.locatorJSON = locatorJSON
        self.title = title
        self.progression = progression
        self.sticker = sticker
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, profileID, bookID, locatorJSON, title, progression, sticker, createdAt, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        // Legacy blobs predate profileID; default to a sentinel so the record
        // survives decode. BookStore rehomes it onto the active profile.
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID) ?? ProfileScopedDefaults.legacyProfileID
        bookID = try container.decode(UUID.self, forKey: .bookID)
        locatorJSON = try container.decode(String.self, forKey: .locatorJSON)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        progression = try container.decode(Double.self, forKey: .progression)
        sticker = try container.decode(BookmarkSticker.self, forKey: .sticker)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
    }

    func withProfileID(_ id: UUID) -> Bookmark {
        Bookmark(id: self.id, profileID: id, bookID: bookID, locatorJSON: locatorJSON, title: title, progression: progression, sticker: sticker, createdAt: createdAt, modifiedAt: modifiedAt)
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
