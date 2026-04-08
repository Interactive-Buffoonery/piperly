import SwiftUI

@MainActor
final class AuthenticatedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false

    private static var cache = NSCache<NSString, UIImage>()

    func load(url: URL) async {
        let cacheKey = url.absoluteString as NSString

        if let cached = Self.cache.object(forKey: cacheKey) {
            image = cached
            return
        }

        isLoading = true

        var request = URLRequest(url: url)
        if let config = OPDSServerConfig.load(), !config.username.isEmpty {
            let credentials = "\(config.username):\(config.password)"
            if let data = credentials.data(using: .utf8) {
                request.setValue(
                    "Basic \(data.base64EncodedString())",
                    forHTTPHeaderField: "Authorization"
                )
            }
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let loaded = UIImage(data: data) {
                Self.cache.setObject(loaded, forKey: cacheKey)
                image = loaded
            }
        } catch {
            // Image failed to load -- placeholder will show
        }

        isLoading = false
    }
}
