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
