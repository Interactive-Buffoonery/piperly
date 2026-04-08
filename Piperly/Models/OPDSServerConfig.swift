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

    static func clear() {
        KeychainService.delete(for: .opdsServerURL)
        KeychainService.delete(for: .opdsUsername)
        KeychainService.delete(for: .opdsPassword)
    }
}
