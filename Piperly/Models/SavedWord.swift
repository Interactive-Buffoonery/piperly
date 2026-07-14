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

struct SavedWord: Identifiable, Codable, Hashable, Sendable, ProfileScoped {
    let id: UUID
    let profileID: UUID
    let word: String
    let displayWord: String
    let bookID: UUID
    let bookTitle: String
    var tapCount: Int
    let savedAt: Date
    var lastTappedAt: Date
    var modifiedAt: Date

    func withProfileID(_ id: UUID) -> SavedWord {
        SavedWord(id: self.id, profileID: id, word: word, displayWord: displayWord, bookID: bookID, bookTitle: bookTitle, tapCount: tapCount, savedAt: savedAt, lastTappedAt: lastTappedAt, modifiedAt: modifiedAt)
    }

    init(
        id: UUID = UUID(),
        profileID: UUID,
        word: String,
        displayWord: String,
        bookID: UUID,
        bookTitle: String,
        tapCount: Int = 1,
        savedAt: Date = .now,
        lastTappedAt: Date = .now,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.profileID = profileID
        self.word = word
        self.displayWord = displayWord
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.tapCount = tapCount
        self.savedAt = savedAt
        self.lastTappedAt = lastTappedAt
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, profileID, word, displayWord, bookID, bookTitle, tapCount, savedAt, lastTappedAt, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        // Legacy blobs predate profileID; default to a sentinel so the record
        // survives decode. BookStore rehomes it onto the active profile.
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID) ?? ProfileScopedDefaults.legacyProfileID
        word = try container.decode(String.self, forKey: .word)
        displayWord = try container.decode(String.self, forKey: .displayWord)
        bookID = try container.decode(UUID.self, forKey: .bookID)
        bookTitle = try container.decode(String.self, forKey: .bookTitle)
        tapCount = try container.decode(Int.self, forKey: .tapCount)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        lastTappedAt = try container.decode(Date.self, forKey: .lastTappedAt)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? lastTappedAt
    }
}
