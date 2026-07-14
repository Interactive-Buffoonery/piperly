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

struct ReaderProfile: Identifiable, Codable, Hashable, Sendable {
    static let defaultName = "Reader"
    static let defaultAvatarSymbol = "person.crop.circle.fill"
    static let defaultColorName = "accent"
    static let defaultVoiceIdentifier = ""
    static let defaultSpeechRate = 0.45
    static let defaultFontSize = 22.0
    static let defaultReaderTheme = "piperly"

    enum NicknameValidationError: Error, Equatable, LocalizedError {
        case empty
        case tooLong
        case containsWhitespace
        case containsDigits
        case containsAccountIdentifier

        var errorDescription: String? {
            switch self {
            case .empty:
                "Enter a nickname."
            case .tooLong:
                "Keep nicknames under 20 characters."
            case .containsWhitespace:
                "Use one nickname, not a full name."
            case .containsDigits:
                "Do not enter birthdays or ages."
            case .containsAccountIdentifier:
                "Do not enter email addresses or Apple IDs."
            }
        }
    }

    let id: UUID
    private(set) var name: String
    var avatarSymbol: String
    var colorName: String
    let createdAt: Date
    var voiceIdentifier: String
    var speechRate: Double
    var fontSize: Double
    var readerTheme: String
    var hasCompletedVoiceSetup: Bool
    var metadataModifiedAt: Date
    var preferencesModifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        avatarSymbol: String = Self.defaultAvatarSymbol,
        colorName: String = Self.defaultColorName,
        createdAt: Date = .now,
        voiceIdentifier: String = Self.defaultVoiceIdentifier,
        speechRate: Double = Self.defaultSpeechRate,
        fontSize: Double = Self.defaultFontSize,
        readerTheme: String = Self.defaultReaderTheme,
        hasCompletedVoiceSetup: Bool = false,
        metadataModifiedAt: Date = .now,
        preferencesModifiedAt: Date = .now
    ) throws {
        self.id = id
        self.name = try Self.validatedNickname(name)
        self.avatarSymbol = avatarSymbol
        self.colorName = colorName
        self.createdAt = createdAt
        self.voiceIdentifier = voiceIdentifier
        self.speechRate = speechRate
        self.fontSize = fontSize
        self.readerTheme = readerTheme
        self.hasCompletedVoiceSetup = hasCompletedVoiceSetup
        self.metadataModifiedAt = metadataModifiedAt
        self.preferencesModifiedAt = preferencesModifiedAt
    }

    init() {
        id = UUID()
        name = Self.defaultName
        avatarSymbol = Self.defaultAvatarSymbol
        colorName = Self.defaultColorName
        createdAt = .now
        voiceIdentifier = Self.defaultVoiceIdentifier
        speechRate = Self.defaultSpeechRate
        fontSize = Self.defaultFontSize
        readerTheme = Self.defaultReaderTheme
        hasCompletedVoiceSetup = false
        metadataModifiedAt = .now
        preferencesModifiedAt = .now
    }

    mutating func updateNickname(_ name: String) throws {
        self.name = try Self.validatedNickname(name)
    }

    static func nicknameValidationError(for name: String) -> NicknameValidationError? {
        do {
            _ = try validatedNickname(name)
            return nil
        } catch let error as NicknameValidationError {
            return error
        } catch {
            return .empty
        }
    }

    /// Non-throwing sanitizer for decode: coerces a legacy or invalid persisted
    /// nickname into a valid one instead of throwing, so a name that was valid
    /// under an older rule (e.g. contained a space or digit) can't wipe the
    /// whole profiles array on upgrade. Validation still throws at create/update.
    private static func sanitizedNickname(_ name: String) -> String {
        if let valid = try? validatedNickname(name) { return valid }
        var stripped = name.trimmingCharacters(in: .whitespacesAndNewlines)
        stripped.removeAll { $0.isWhitespace || $0.isNumber || $0 == "@" || $0 == "." }
        let trimmed = String(stripped.prefix(20))
        return (try? validatedNickname(trimmed)) ?? defaultName
    }

    private static func validatedNickname(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw NicknameValidationError.empty
        }
        if trimmed.count > 20 {
            throw NicknameValidationError.tooLong
        }
        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            throw NicknameValidationError.containsWhitespace
        }
        if trimmed.rangeOfCharacter(from: .decimalDigits) != nil {
            throw NicknameValidationError.containsDigits
        }
        if trimmed.contains("@") || trimmed.contains(".") {
            throw NicknameValidationError.containsAccountIdentifier
        }
        return trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarSymbol
        case colorName
        case createdAt
        case voiceIdentifier
        case speechRate
        case fontSize
        case readerTheme
        case hasCompletedVoiceSetup
        case metadataModifiedAt
        case preferencesModifiedAt
        case modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = Self.sanitizedNickname(try container.decode(String.self, forKey: .name))
        avatarSymbol = try container.decode(String.self, forKey: .avatarSymbol)
        colorName = try container.decode(String.self, forKey: .colorName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        voiceIdentifier = try container.decodeIfPresent(String.self, forKey: .voiceIdentifier)
            ?? Self.defaultVoiceIdentifier
        speechRate = try container.decodeIfPresent(Double.self, forKey: .speechRate)
            ?? Self.defaultSpeechRate
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
            ?? Self.defaultFontSize
        readerTheme = try container.decodeIfPresent(String.self, forKey: .readerTheme)
            ?? Self.defaultReaderTheme
        hasCompletedVoiceSetup = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedVoiceSetup)
            ?? false
        let legacyModifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        metadataModifiedAt = try container.decodeIfPresent(Date.self, forKey: .metadataModifiedAt)
            ?? legacyModifiedAt
        preferencesModifiedAt = try container.decodeIfPresent(Date.self, forKey: .preferencesModifiedAt)
            ?? legacyModifiedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(avatarSymbol, forKey: .avatarSymbol)
        try container.encode(colorName, forKey: .colorName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(voiceIdentifier, forKey: .voiceIdentifier)
        try container.encode(speechRate, forKey: .speechRate)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(readerTheme, forKey: .readerTheme)
        try container.encode(hasCompletedVoiceSetup, forKey: .hasCompletedVoiceSetup)
        try container.encode(metadataModifiedAt, forKey: .metadataModifiedAt)
        try container.encode(preferencesModifiedAt, forKey: .preferencesModifiedAt)
    }
}
