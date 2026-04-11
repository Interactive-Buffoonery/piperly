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

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    init(hex string: String, opacity: Double = 1.0) {
        let hex = string.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(hex: value, opacity: opacity)
    }
}

enum Piperly {
    enum Colors {
        // Surfaces
        static let background = Color(hex: 0x1C1C2E)
        static let surface = Color(hex: 0x252540)
        static let surfaceElevated = Color(hex: 0x2E2E4A)
        static let border = Color(hex: 0x3A3A55)

        // Text
        static let textPrimary = Color(hex: 0xE8E8F0)
        static let textSecondary = Color(hex: 0x9090A8)
        static let textTertiary = Color(hex: 0x606078)

        // Semantic
        static let accent = Color(hex: 0x7CD4C8)
        static let success = Color(hex: 0x7BC8A4)
        static let warning = Color(hex: 0xD4A76A)
        static let error = Color(hex: 0xD47C7C)
        static let info = Color(hex: 0x9B8EC4)

        // Extended palette
        static let teal = Color(hex: 0x7CD4C8)
        static let tan = Color(hex: 0xC8A87B)
        static let green = Color(hex: 0x8BC47B)
    }
}
