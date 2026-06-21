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
import CryptoKit

@MainActor
final class PINManager: ObservableObject {
    @Published private(set) var isPINSet: Bool

    init() {
        isPINSet = KeychainService.exists(for: .parentalPIN)
    }

    func setPIN(_ pin: String) throws {
        let hash = Self.hash(pin)
        try KeychainService.save(hash, for: .parentalPIN)
        isPINSet = true
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let stored = KeychainService.load(for: .parentalPIN) else {
            return false
        }
        return stored == Self.hash(pin)
    }

    func removePIN() {
        KeychainService.delete(for: .parentalPIN)
        isPINSet = false
    }

    private static func hash(_ pin: String) -> String {
        let data = Data(pin.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
