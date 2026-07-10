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

    /// Legacy blobs predate `profileID`; default it to a sentinel so the record
    /// survives decode. BookStore rehomes the sentinel onto the active profile.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        profileID = try c.decodeIfPresent(UUID.self, forKey: .profileID) ?? ProfileScopedDefaults.legacyProfileID
        word = try c.decode(String.self, forKey: .word)
        displayWord = try c.decode(String.self, forKey: .displayWord)
        bookID = try c.decode(UUID.self, forKey: .bookID)
        bookTitle = try c.decode(String.self, forKey: .bookTitle)
        tapCount = try c.decode(Int.self, forKey: .tapCount)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        lastTappedAt = try c.decode(Date.self, forKey: .lastTappedAt)
    }

    func withProfileID(_ id: UUID) -> SavedWord {
        SavedWord(id: self.id, profileID: id, word: word, displayWord: displayWord, bookID: bookID, bookTitle: bookTitle, tapCount: tapCount, savedAt: savedAt, lastTappedAt: lastTappedAt)
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
        lastTappedAt: Date = .now
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
    }
}
