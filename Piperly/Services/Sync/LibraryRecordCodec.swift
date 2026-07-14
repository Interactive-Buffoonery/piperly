// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import CloudKit
import Foundation

enum LibraryRecordCodecError: Error, Equatable {
    case unsupportedRecordType(String)
    case missingField(String)
    case invalidField(String)
}

enum LibraryRecordCodec {
    static let zoneID = CKRecordZone.ID(zoneName: "PiperlyLibrary", ownerName: CKCurrentUserDefaultName)

    static func encode(_ value: LibraryRecord, systemFields: Data? = nil) throws -> CKRecord {
        let reference = value.reference
        let recordID = CKRecord.ID(recordName: reference.recordName, zoneID: zoneID)
        let record: CKRecord
        if let systemFields,
           let decoded = try? CKRecord(systemFieldsData: systemFields),
           decoded.recordID == recordID {
            record = decoded
        } else {
            record = CKRecord(recordType: reference.recordType, recordID: recordID)
        }

        switch value {
        case .book(let book):
            record["localID"] = book.id.uuidString.lowercased()
            record["title"] = book.title
            record["author"] = book.author
            record["originalExtension"] = book.originalExtension
            record["hasCover"] = book.hasCover ? 1 : 0
            record["modifiedAt"] = book.modifiedAt
        case .readerProfile(let profile):
            record["nickname"] = profile.nickname
            record["avatarSymbol"] = profile.avatarSymbol
            record["colorName"] = profile.colorName
            record["createdAt"] = profile.createdAt
            record["modifiedAt"] = profile.modifiedAt
        case .readerPreferences(let preferences):
            record["profileID"] = preferences.profileID.uuidString.lowercased()
            record["voiceIdentifier"] = preferences.voiceIdentifier
            record["speechRate"] = preferences.speechRate
            record["fontSize"] = preferences.fontSize
            record["readerTheme"] = preferences.readerTheme
            record["hasCompletedVoiceSetup"] = preferences.hasCompletedVoiceSetup ? 1 : 0
            record["modifiedAt"] = preferences.modifiedAt
        case .readingState(let state):
            record["profileID"] = state.profileID.uuidString.lowercased()
            record["bookIdentity"] = state.bookIdentity.lowercased()
            record["progression"] = state.progression
            record["locatorJSON"] = state.locatorJSON
            record["modifiedAt"] = state.modifiedAt
        case .bookmark(let bookmark):
            record["profileID"] = bookmark.profileID.uuidString.lowercased()
            record["bookIdentity"] = bookmark.bookIdentity.lowercased()
            record["locatorJSON"] = bookmark.locatorJSON
            record["title"] = bookmark.title
            record["progression"] = bookmark.progression
            record["sticker"] = bookmark.sticker
            record["createdAt"] = bookmark.createdAt
            record["modifiedAt"] = bookmark.modifiedAt
        case .savedWord(let word):
            record["profileID"] = word.profileID.uuidString.lowercased()
            record["bookIdentity"] = word.bookIdentity.lowercased()
            record["canonicalWord"] = word.canonicalWord
            record["displayWord"] = word.displayWord
            record["bookTitle"] = word.bookTitle
            record["tapCount"] = word.tapCount
            record["savedAt"] = word.savedAt
            record["lastTappedAt"] = word.lastTappedAt
            record["modifiedAt"] = word.modifiedAt
        }
        return record
    }

    static func decode(_ record: CKRecord) throws -> LibraryRecord {
        switch record.recordType {
        case "Book":
            return .book(SyncedBook(
                id: try uuid("localID", record),
                contentIdentity: record.recordID.recordName.lowercased(),
                title: try string("title", record),
                author: try string("author", record),
                originalExtension: try string("originalExtension", record),
                hasCover: try bool("hasCover", record),
                modifiedAt: try date("modifiedAt", record)
            ))
        case "ReaderProfile":
            return .readerProfile(SyncedReaderProfile(
                id: try recordUUID(record, prefix: "profile-"),
                nickname: try string("nickname", record),
                avatarSymbol: try string("avatarSymbol", record),
                colorName: try string("colorName", record),
                createdAt: try date("createdAt", record),
                modifiedAt: try date("modifiedAt", record)
            ))
        case "ReaderPreferences":
            return .readerPreferences(SyncedReaderPreferences(
                profileID: try uuid("profileID", record),
                voiceIdentifier: try string("voiceIdentifier", record),
                speechRate: try double("speechRate", record),
                fontSize: try double("fontSize", record),
                readerTheme: try string("readerTheme", record),
                hasCompletedVoiceSetup: try bool("hasCompletedVoiceSetup", record),
                modifiedAt: try date("modifiedAt", record)
            ))
        case "ReadingState":
            return .readingState(SyncedReadingState(
                profileID: try uuid("profileID", record),
                bookIdentity: try string("bookIdentity", record),
                progression: try double("progression", record),
                locatorJSON: record["locatorJSON"] as? String,
                modifiedAt: try date("modifiedAt", record)
            ))
        case "Bookmark":
            return .bookmark(SyncedBookmark(
                id: try recordUUID(record, prefix: "bookmark-"),
                profileID: try uuid("profileID", record),
                bookIdentity: try string("bookIdentity", record),
                locatorJSON: try string("locatorJSON", record),
                title: record["title"] as? String,
                progression: try double("progression", record),
                sticker: try string("sticker", record),
                createdAt: try date("createdAt", record),
                modifiedAt: try date("modifiedAt", record)
            ))
        case "SavedWord":
            return .savedWord(SyncedSavedWord(
                id: try recordUUID(record, prefix: "word-"),
                profileID: try uuid("profileID", record),
                bookIdentity: try string("bookIdentity", record),
                canonicalWord: try string("canonicalWord", record),
                displayWord: try string("displayWord", record),
                bookTitle: try string("bookTitle", record),
                tapCount: try int("tapCount", record),
                savedAt: try date("savedAt", record),
                lastTappedAt: try date("lastTappedAt", record),
                modifiedAt: try date("modifiedAt", record)
            ))
        default:
            throw LibraryRecordCodecError.unsupportedRecordType(record.recordType)
        }
    }

    static func systemFieldsData(for record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private static func string(_ key: String, _ record: CKRecord) throws -> String {
        guard let value = record[key] as? String else { throw LibraryRecordCodecError.missingField(key) }
        return value
    }

    private static func date(_ key: String, _ record: CKRecord) throws -> Date {
        guard let value = record[key] as? Date else { throw LibraryRecordCodecError.missingField(key) }
        return value
    }

    private static func double(_ key: String, _ record: CKRecord) throws -> Double {
        guard let value = record[key] as? NSNumber else { throw LibraryRecordCodecError.missingField(key) }
        return value.doubleValue
    }

    private static func int(_ key: String, _ record: CKRecord) throws -> Int {
        guard let value = record[key] as? NSNumber else { throw LibraryRecordCodecError.missingField(key) }
        return value.intValue
    }

    private static func bool(_ key: String, _ record: CKRecord) throws -> Bool {
        guard let value = record[key] as? NSNumber else { throw LibraryRecordCodecError.missingField(key) }
        return value.boolValue
    }

    private static func uuid(_ key: String, _ record: CKRecord) throws -> UUID {
        guard let value = UUID(uuidString: try string(key, record)) else {
            throw LibraryRecordCodecError.invalidField(key)
        }
        return value
    }

    private static func recordUUID(_ record: CKRecord, prefix: String) throws -> UUID {
        guard record.recordID.recordName.hasPrefix(prefix),
              let value = UUID(uuidString: String(record.recordID.recordName.dropFirst(prefix.count))) else {
            throw LibraryRecordCodecError.invalidField("recordName")
        }
        return value
    }
}

private extension CKRecord {
    convenience init?(systemFieldsData: Data) throws {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: systemFieldsData)
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        self.init(coder: unarchiver)
    }
}
