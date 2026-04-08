import SwiftUI

struct Voice: Identifiable, Codable {
    let id: Int
    let name: String
    let language: String
    let gender: Gender
    let grade: Grade
    var avatarColor: String

    enum Gender: String, Codable {
        case female, male
    }

    enum Grade: String, Codable {
        case a, aMinus, bMinus, cPlus
    }

    static let curated: [Voice] = [
        Voice(id: 3, name: "Heart", language: "en-US", gender: .female, grade: .a, avatarColor: "accent"),
        Voice(id: 2, name: "Bella", language: "en-US", gender: .female, grade: .aMinus, avatarColor: "success"),
        Voice(id: 6, name: "Nicole", language: "en-US", gender: .female, grade: .bMinus, avatarColor: "info"),
        Voice(id: 21, name: "Emma", language: "en-GB", gender: .female, grade: .bMinus, avatarColor: "teal"),
        Voice(id: 18, name: "Puck", language: "en-US", gender: .male, grade: .cPlus, avatarColor: "warning"),
        Voice(id: 14, name: "Fenrir", language: "en-US", gender: .male, grade: .cPlus, avatarColor: "tan"),
        Voice(id: 16, name: "Michael", language: "en-US", gender: .male, grade: .cPlus, avatarColor: "green"),
    ]

    var color: Color {
        switch avatarColor {
        case "accent": Piperly.Colors.accent
        case "success": Piperly.Colors.success
        case "info": Piperly.Colors.info
        case "teal": Piperly.Colors.teal
        case "warning": Piperly.Colors.warning
        case "tan": Piperly.Colors.tan
        case "green": Piperly.Colors.green
        default: Piperly.Colors.accent
        }
    }
}
