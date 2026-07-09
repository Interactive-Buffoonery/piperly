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
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        contentIdentity: String,
        title: String,
        author: String,
        fileName: String,
        coverImageName: String? = nil,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.contentIdentity = contentIdentity
        self.title = title
        self.author = author
        self.fileName = fileName
        self.coverImageName = coverImageName
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, contentIdentity, title, author, fileName, coverImageName, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        // Legacy blobs predate contentIdentity; default to "" so the book
        // survives decode. BookStore.backfillContentIdentities() hashes the
        // on-disk file and migrates the filename on load.
        contentIdentity = try container.decodeIfPresent(String.self, forKey: .contentIdentity) ?? ""
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        fileName = try container.decode(String.self, forKey: .fileName)
        coverImageName = try container.decodeIfPresent(String.self, forKey: .coverImageName)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    }
}
