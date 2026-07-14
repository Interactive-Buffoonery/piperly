// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import Foundation

enum LibraryConflictResolver {
    static func merge(local: LibraryRecord, remote: LibraryRecord) -> LibraryRecord {
        switch (local, remote) {
        case (.book(let local), .book(let remote)):
            return .book(merge(local: local, remote: remote))
        case (.readerProfile(let local), .readerProfile(let remote)):
            return .readerProfile(local.modifiedAt >= remote.modifiedAt ? local : remote)
        case (.readerPreferences(let local), .readerPreferences(let remote)):
            return .readerPreferences(local.modifiedAt >= remote.modifiedAt ? local : remote)
        case (.readingState(let local), .readingState(let remote)):
            return .readingState(merge(local: local, remote: remote))
        case (.bookmark(let local), .bookmark(let remote)):
            return .bookmark(local.modifiedAt >= remote.modifiedAt ? local : remote)
        case (.savedWord(let local), .savedWord(let remote)):
            return .savedWord(merge(local: local, remote: remote))
        default:
            return remote
        }
    }

    private static func merge(local: SyncedBook, remote: SyncedBook) -> SyncedBook {
        let newest = local.modifiedAt >= remote.modifiedAt ? local : remote
        let older = local.modifiedAt >= remote.modifiedAt ? remote : local
        return SyncedBook(
            id: local.id,
            contentIdentity: local.contentIdentity,
            title: newest.title.isEmpty ? older.title : newest.title,
            author: newest.author.isEmpty ? older.author : newest.author,
            originalExtension: newest.originalExtension,
            hasCover: newest.hasCover || older.hasCover,
            modifiedAt: max(local.modifiedAt, remote.modifiedAt)
        )
    }

    // Reading progress must not regress on a device-clock lie. `modifiedAt` is a
    // wall clock on the writing device; a skewed-future clock would otherwise let a
    // stale, lower progression win forever. Only accept a lower progression when the
    // reader genuinely moved to a different position (locator changed) -- a same-locator
    // decrease is treated as clock skew and the higher progression is kept.
    static func merge(local: SyncedReadingState, remote: SyncedReadingState) -> SyncedReadingState {
        let newest = local.modifiedAt >= remote.modifiedAt ? local : remote
        let older = local.modifiedAt >= remote.modifiedAt ? remote : local
        if newest.progression < older.progression, newest.locatorJSON == older.locatorJSON {
            return older
        }
        return newest
    }

    private static func merge(local: SyncedSavedWord, remote: SyncedSavedWord) -> SyncedSavedWord {
        let newest = local.modifiedAt >= remote.modifiedAt ? local : remote
        return SyncedSavedWord(
            id: newest.id,
            profileID: newest.profileID,
            bookIdentity: newest.bookIdentity,
            canonicalWord: newest.canonicalWord,
            displayWord: newest.displayWord,
            bookTitle: newest.bookTitle,
            tapCount: max(local.tapCount, remote.tapCount),
            savedAt: min(local.savedAt, remote.savedAt),
            lastTappedAt: max(local.lastTappedAt, remote.lastTappedAt),
            modifiedAt: max(local.modifiedAt, remote.modifiedAt)
        )
    }
}
