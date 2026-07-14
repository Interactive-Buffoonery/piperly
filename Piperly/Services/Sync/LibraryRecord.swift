// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import Foundation

struct SyncedBook: Codable, Sendable, Equatable {
    let id: UUID
    let contentIdentity: String
    var title: String
    var author: String
    let originalExtension: String
    var hasCover: Bool
    var modifiedAt: Date
}

struct SyncedReaderProfile: Codable, Sendable, Equatable {
    let id: UUID
    var nickname: String
    var avatarSymbol: String
    var colorName: String
    let createdAt: Date
    var modifiedAt: Date
}

struct SyncedReaderPreferences: Codable, Sendable, Equatable {
    let profileID: UUID
    var voiceIdentifier: String
    var speechRate: Double
    var fontSize: Double
    var readerTheme: String
    var hasCompletedVoiceSetup: Bool
    var modifiedAt: Date
}

struct SyncedReadingState: Codable, Sendable, Equatable {
    let profileID: UUID
    let bookIdentity: String
    var progression: Double
    var locatorJSON: String?
    var modifiedAt: Date
}

struct SyncedBookmark: Codable, Sendable, Equatable {
    let id: UUID
    let profileID: UUID
    let bookIdentity: String
    var locatorJSON: String
    var title: String?
    var progression: Double
    var sticker: String
    let createdAt: Date
    var modifiedAt: Date
}

struct SyncedSavedWord: Codable, Sendable, Equatable {
    let id: UUID
    let profileID: UUID
    let bookIdentity: String
    var canonicalWord: String
    var displayWord: String
    var bookTitle: String
    var tapCount: Int
    var savedAt: Date
    var lastTappedAt: Date
    var modifiedAt: Date
}

struct LibraryRecordReference: Codable, Sendable, Hashable {
    let recordType: String
    let recordName: String
}

enum LibraryRecord: Codable, Sendable, Equatable {
    case book(SyncedBook)
    case readerProfile(SyncedReaderProfile)
    case readerPreferences(SyncedReaderPreferences)
    case readingState(SyncedReadingState)
    case bookmark(SyncedBookmark)
    case savedWord(SyncedSavedWord)

    var reference: LibraryRecordReference {
        switch self {
        case .book(let value):
            LibraryRecordReference(recordType: "Book", recordName: value.contentIdentity.lowercased())
        case .readerProfile(let value):
            LibraryRecordReference(recordType: "ReaderProfile", recordName: "profile-\(value.id.cloudRecordName)")
        case .readerPreferences(let value):
            LibraryRecordReference(
                recordType: "ReaderPreferences",
                recordName: "preferences-\(value.profileID.cloudRecordName)"
            )
        case .readingState(let value):
            LibraryRecordReference(
                recordType: "ReadingState",
                recordName: "reading-\(value.profileID.cloudRecordName)-\(value.bookIdentity.lowercased())"
            )
        case .bookmark(let value):
            LibraryRecordReference(recordType: "Bookmark", recordName: "bookmark-\(value.id.cloudRecordName)")
        case .savedWord(let value):
            LibraryRecordReference(recordType: "SavedWord", recordName: "word-\(value.id.cloudRecordName)")
        }
    }
}

extension LibraryRecord {
    var remoteApplicationOrder: Int {
        switch self {
        case .book, .readerProfile:
            0
        case .readerPreferences, .readingState, .bookmark, .savedWord:
            1
        }
    }
}

private extension UUID {
    var cloudRecordName: String { uuidString.lowercased() }
}
