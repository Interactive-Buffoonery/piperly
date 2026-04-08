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
        if let authValue = OPDSServerConfig.load()?.authorizationHeaderValue() {
            request.setValue(authValue, forHTTPHeaderField: "Authorization")
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
