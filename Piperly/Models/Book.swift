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

struct Book: Identifiable, Codable {
    let id: UUID
    let title: String
    let author: String
    let fileName: String
    var coverImageName: String?

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        fileName: String,
        coverImageName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.fileName = fileName
        self.coverImageName = coverImageName
    }
}
