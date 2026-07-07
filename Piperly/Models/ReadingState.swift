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

struct ReadingState: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let profileID: UUID
    let bookID: UUID
    var lastReadProgression: Double
    var lastReadLocatorJSON: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        profileID: UUID,
        bookID: UUID,
        lastReadProgression: Double = 0.0,
        lastReadLocatorJSON: String? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.profileID = profileID
        self.bookID = bookID
        self.lastReadProgression = lastReadProgression
        self.lastReadLocatorJSON = lastReadLocatorJSON
        self.updatedAt = updatedAt
    }
}
