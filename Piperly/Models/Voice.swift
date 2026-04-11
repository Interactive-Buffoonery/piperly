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

import AVFoundation
import SwiftUI

struct Voice: Identifiable {
    let id: String
    let name: String
    let language: String
    let quality: Quality

    enum Quality: String, Comparable {
        case premium = "Premium"
        case enhanced = "Enhanced"
        case standard = "Standard"

        private var sortOrder: Int {
            switch self {
            case .premium: 0
            case .enhanced: 1
            case .standard: 2
            }
        }

        static func < (lhs: Quality, rhs: Quality) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    static func availableVoices() -> [Voice] {
        let allEnglish = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en") }

        let highQuality = allEnglish.filter { $0.quality == .premium || $0.quality == .enhanced }
        let voicesToShow = highQuality.isEmpty ? allEnglish : highQuality

        return voicesToShow
            .map { voice in
                let quality: Quality = switch voice.quality {
                case .premium: .premium
                case .enhanced: .enhanced
                default: .standard
                }
                return Voice(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    quality: quality
                )
            }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return lhs.quality < rhs.quality
                }
                return lhs.name < rhs.name
            }
    }

    private static let palette: [Color] = [
        Piperly.Colors.accent,
        Piperly.Colors.success,
        Piperly.Colors.info,
        Piperly.Colors.teal,
        Piperly.Colors.warning,
        Piperly.Colors.tan,
        Piperly.Colors.green,
    ]

    var color: Color {
        let hash = abs(name.hashValue)
        return Self.palette[hash % Self.palette.count]
    }
}
