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
