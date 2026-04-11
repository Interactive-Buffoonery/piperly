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

struct OPDSServerConfig: Sendable {
    var url: URL
    var username: String
    var password: String

    var isConfigured: Bool {
        !url.absoluteString.isEmpty
    }

    static func load() -> OPDSServerConfig? {
        guard let urlString = KeychainService.load(for: .opdsServerURL),
              let url = URL(string: urlString)
        else {
            return nil
        }

        return OPDSServerConfig(
            url: url,
            username: KeychainService.load(for: .opdsUsername) ?? "",
            password: KeychainService.load(for: .opdsPassword) ?? ""
        )
    }

    func save() throws {
        try KeychainService.save(url.absoluteString, for: .opdsServerURL)
        try KeychainService.save(username, for: .opdsUsername)
        try KeychainService.save(password, for: .opdsPassword)
    }

    func authorizationHeaderValue() -> String? {
        guard !username.isEmpty,
              let data = "\(username):\(password)".data(using: .utf8)
        else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    static func clear() {
        KeychainService.delete(for: .opdsServerURL)
        KeychainService.delete(for: .opdsUsername)
        KeychainService.delete(for: .opdsPassword)
    }
}
