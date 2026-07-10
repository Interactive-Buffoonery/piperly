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

struct ReaderProfile: Identifiable, Codable, Hashable, Sendable {
    static let defaultName = "Reader"
    static let defaultAvatarSymbol = "person.crop.circle.fill"
    static let defaultColorName = "accent"

    let id: UUID
    var name: String
    var avatarSymbol: String
    var colorName: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = Self.defaultName,
        avatarSymbol: String = Self.defaultAvatarSymbol,
        colorName: String = Self.defaultColorName,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.avatarSymbol = avatarSymbol
        self.colorName = colorName
        self.createdAt = createdAt
    }
}
