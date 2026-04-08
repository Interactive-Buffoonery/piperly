import Foundation
import CryptoKit

@MainActor
final class PINManager: ObservableObject {
    @Published private(set) var isPINSet: Bool

    init() {
        isPINSet = KeychainService.exists(for: .parentalPIN)
    }

    func setPIN(_ pin: String) {
        let hash = Self.hash(pin)
        try? KeychainService.save(hash, for: .parentalPIN)
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
