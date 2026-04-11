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
