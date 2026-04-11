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

import ReadiumNavigator

enum ReaderTheme: String, CaseIterable, Identifiable, Sendable {
    case piperly
    case sunshine
    case ocean
    case forest
    case lavender
    case nightOwl
    case cozy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .piperly: "Piperly"
        case .sunshine: "Sunshine"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .lavender: "Lavender"
        case .nightOwl: "Night Owl"
        case .cozy: "Cozy"
        }
    }

    var backgroundColor: String {
        switch self {
        case .piperly: "#1C1C2E"
        case .sunshine: "#FFF0D4"
        case .ocean: "#E3F2FD"
        case .forest: "#E8F5E9"
        case .lavender: "#F3E5F5"
        case .nightOwl: "#1C1C1E"
        case .cozy: "#F5F0E1"
        }
    }

    var textColor: String {
        switch self {
        case .piperly: "#E8E8F0"
        case .sunshine: "#2D2006"
        case .ocean: "#1A237E"
        case .forest: "#1B5E20"
        case .lavender: "#4A148C"
        case .nightOwl: "#E0E0E0"
        case .cozy: "#5D4037"
        }
    }

    var fontFamily: FontFamily {
        switch self {
        case .piperly, .sunshine, .ocean, .lavender: .sansSerif
        case .forest, .nightOwl, .cozy: .serif
        }
    }

    var isDark: Bool {
        switch self {
        case .piperly, .nightOwl: true
        case .sunshine, .ocean, .forest, .lavender, .cozy: false
        }
    }

    var linkColor: String { textColor }

    var highlightColor: String {
        let hex = textColor.dropFirst()
        let r = Int(hex.prefix(2), radix: 16) ?? 0
        let g = Int(hex.dropFirst(2).prefix(2), radix: 16) ?? 0
        let b = Int(hex.dropFirst(4).prefix(2), radix: 16) ?? 0
        return "rgba(\(r), \(g), \(b), 0.3)"
    }

    var cssVariablesScript: String {
        """
        (function() {
            var r = document.documentElement.style;
            r.setProperty('--piperly-bg', '\(backgroundColor)');
            r.setProperty('--piperly-text', '\(textColor)');
            r.setProperty('--piperly-accent', '\(linkColor)');
            r.setProperty('--piperly-highlight', '\(highlightColor)');
        })();
        """
    }

    func epubPreferences(fontSize: Double) -> EPUBPreferences {
        EPUBPreferences(
            backgroundColor: ReadiumNavigator.Color(hex: backgroundColor),
            fontFamily: fontFamily,
            fontSize: fontSize / 22.0,
            hyphens: false,
            lineHeight: 1.7,
            publisherStyles: false,
            scroll: false,
            textColor: ReadiumNavigator.Color(hex: textColor)
        )
    }
}
