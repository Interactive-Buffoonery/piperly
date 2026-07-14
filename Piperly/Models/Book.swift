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
    let contentIdentity: String
    let title: String
    let author: String
    let fileName: String
    var coverImageName: String?

    init(
        id: UUID = UUID(),
        contentIdentity: String,
        title: String,
        author: String,
        fileName: String,
        coverImageName: String? = nil
    ) {
        self.id = id
        self.contentIdentity = contentIdentity
        self.title = title
        self.author = author
        self.fileName = fileName
        self.coverImageName = coverImageName
    }

    /// Legacy blobs predate `contentIdentity`; default it to "" so the book
    /// survives decode. BookStore backfills the real hash (and migrates the
    /// filename) on load. See BookStore.backfillContentIdentities().
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        contentIdentity = try c.decodeIfPresent(String.self, forKey: .contentIdentity) ?? ""
        title = try c.decode(String.self, forKey: .title)
        author = try c.decode(String.self, forKey: .author)
        fileName = try c.decode(String.self, forKey: .fileName)
        coverImageName = try c.decodeIfPresent(String.self, forKey: .coverImageName)
    }
}
