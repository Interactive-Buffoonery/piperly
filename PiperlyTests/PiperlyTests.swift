// swiftlint:disable force_unwrapping
import Testing
import Foundation
@testable import Piperly

// MARK: - Book

@Suite("Book")
struct BookTests {
    @Test func defaultValues() {
        let book = Book(title: "Test", author: "Author", fileName: "test.epub")
        #expect(book.coverImageName == nil)
    }

    @Test func codableRoundTrip() throws {
        let book = Book(title: "The Secret Garden", author: "Frances Hodgson Burnett", fileName: "secret-garden.epub")
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(Book.self, from: data)
        #expect(decoded.id == book.id)
        #expect(decoded.title == book.title)
        #expect(decoded.author == book.author)
        #expect(decoded.fileName == book.fileName)
    }

    @Test func codableWithAllFields() throws {
        let book = Book(
            title: "Test",
            author: "Author",
            fileName: "test.epub",
            coverImageName: "cover.jpg"
        )
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(Book.self, from: data)
        #expect(decoded.coverImageName == "cover.jpg")
    }
}

// MARK: - Bookmark

@Suite("Bookmark")
struct BookmarkTests {
    @Test func defaultValues() {
        let now = Date.now
        let profileID = UUID()
        let bookmark = Bookmark(
            profileID: profileID,
            bookID: UUID(),
            locatorJSON: "{}",
            title: "Chapter 1",
            progression: 0.5,
            sticker: .star
        )
        #expect(bookmark.title == "Chapter 1")
        #expect(bookmark.profileID == profileID)
        #expect(bookmark.progression == 0.5)
        #expect(bookmark.sticker == .star)
        #expect(bookmark.createdAt.timeIntervalSince(now) < 1)
    }

    @Test func codableRoundTrip() throws {
        let bookmark = Bookmark(
            profileID: UUID(),
            bookID: UUID(),
            locatorJSON: "{\"href\":\"/ch2\"}",
            title: "Chapter 2",
            progression: 0.33,
            sticker: .heart
        )
        let data = try JSONEncoder().encode(bookmark)
        let decoded = try JSONDecoder().decode(Bookmark.self, from: data)
        #expect(decoded.id == bookmark.id)
        #expect(decoded.profileID == bookmark.profileID)
        #expect(decoded.bookID == bookmark.bookID)
        #expect(decoded.locatorJSON == bookmark.locatorJSON)
        #expect(decoded.title == bookmark.title)
        #expect(decoded.progression == bookmark.progression)
        #expect(decoded.sticker == bookmark.sticker)
    }

    @Test func allStickersSurviveCoding() throws {
        for sticker in BookmarkSticker.allCases {
            let bookmark = Bookmark(
                profileID: UUID(),
                bookID: UUID(),
                locatorJSON: "{}",
                title: nil,
                progression: 0.0,
                sticker: sticker
            )
            let data = try JSONEncoder().encode(bookmark)
            let decoded = try JSONDecoder().decode(Bookmark.self, from: data)
            #expect(decoded.sticker == sticker)
        }
    }
}

// MARK: - Legacy / corrupt decode (S1 data-loss guard)

@Suite("LegacyDecode")
struct LegacyDecodeTests {
    // Legacy blobs persisted before profiles existed have no profileID key.
    @Test func legacyBookmarkWithoutProfileIDSurvives() throws {
        let json = """
        {"id":"\(UUID().uuidString)","bookID":"\(UUID().uuidString)","locatorJSON":"{}","progression":0.5,"sticker":"star","createdAt":0}
        """
        let decoded = try JSONDecoder().decode(Bookmark.self, from: Data(json.utf8))
        #expect(decoded.profileID == ProfileScopedDefaults.legacyProfileID)
        #expect(decoded.progression == 0.5)
    }

    @Test func legacySavedWordWithoutProfileIDSurvives() throws {
        let json = """
        {"id":"\(UUID().uuidString)","word":"cat","displayWord":"cat","bookID":"\(UUID().uuidString)","bookTitle":"T","tapCount":2,"savedAt":0,"lastTappedAt":0}
        """
        let decoded = try JSONDecoder().decode(SavedWord.self, from: Data(json.utf8))
        #expect(decoded.profileID == ProfileScopedDefaults.legacyProfileID)
        #expect(decoded.word == "cat")
    }

    // One un-decodable element must NOT drop the whole array to []. Before the
    // tolerant loader, seeding this blob wiped every bookmark on next save.
    @Test @MainActor func corruptElementDoesNotWipeStore() throws {
        let key = "piperly_bookmarks"
        let good = Bookmark(profileID: UUID(), bookID: UUID(), locatorJSON: "{}", title: nil, progression: 0.3, sticker: .heart)
        let goodJSON = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        let blob = "[\(goodJSON),{\"garbage\":true}]"
        UserDefaults.standard.set(Data(blob.utf8), forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let store = BookStore()
        #expect(store.bookmarks.contains { $0.id == good.id })
    }

    // Total corruption (non-empty bytes, zero recovered) must not be overwritten
    // by an empty save, so a later real save can't erase recoverable bytes.
    @Test @MainActor func totalCorruptionIsNotOverwrittenByEmptySave() {
        let key = "piperly_saved_words"
        UserDefaults.standard.set(Data("[{\"garbage\":true}]".utf8), forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let store = BookStore()
        #expect(store.savedWords.isEmpty)
        store.saveSavedWords()  // empty save must be refused
        let after = UserDefaults.standard.data(forKey: key)
        #expect(after == Data("[{\"garbage\":true}]".utf8))
    }
}

// MARK: - BookmarkSticker

@Suite("BookmarkSticker")
struct BookmarkStickerTests {
    @Test func symbols() {
        #expect(BookmarkSticker.star.symbol == "star.fill")
        #expect(BookmarkSticker.heart.symbol == "heart.fill")
        #expect(BookmarkSticker.lightbulb.symbol == "lightbulb.fill")
        #expect(BookmarkSticker.question.symbol == "questionmark.circle.fill")
        #expect(BookmarkSticker.bookmark.symbol == "bookmark.fill")
    }

    @Test func labels() {
        #expect(BookmarkSticker.star.label == "Favorite")
        #expect(BookmarkSticker.heart.label == "Love it")
        #expect(BookmarkSticker.lightbulb.label == "Learned")
        #expect(BookmarkSticker.question.label == "Question")
        #expect(BookmarkSticker.bookmark.label == "Save")
    }

    @Test func allCasesCount() {
        #expect(BookmarkSticker.allCases.count == 5)
    }
}

// MARK: - SavedWord

@Suite("SavedWord")
struct SavedWordTests {
    @Test func defaultValues() {
        let now = Date.now
        let profileID = UUID()
        let word = SavedWord(
            profileID: profileID,
            word: "adventure",
            displayWord: "Adventure",
            bookID: UUID(),
            bookTitle: "Test Book"
        )
        #expect(word.tapCount == 1)
        #expect(word.savedAt.timeIntervalSince(now) < 1)
        #expect(word.lastTappedAt.timeIntervalSince(now) < 1)
        #expect(word.word == "adventure")
        #expect(word.displayWord == "Adventure")
        #expect(word.profileID == profileID)
    }

    @Test func codableRoundTrip() throws {
        let word = SavedWord(
            profileID: UUID(),
            word: "mysterious",
            displayWord: "Mysterious",
            bookID: UUID(),
            bookTitle: "The Secret Garden",
            tapCount: 3
        )
        let data = try JSONEncoder().encode(word)
        let decoded = try JSONDecoder().decode(SavedWord.self, from: data)
        #expect(decoded.id == word.id)
        #expect(decoded.profileID == word.profileID)
        #expect(decoded.word == word.word)
        #expect(decoded.displayWord == word.displayWord)
        #expect(decoded.bookID == word.bookID)
        #expect(decoded.bookTitle == word.bookTitle)
        #expect(decoded.tapCount == 3)
    }
}

// MARK: - ReaderProfile

@Suite("ReaderProfile")
struct ReaderProfileTests {
    @Test func defaultValuesAvoidPersonalInformation() {
        let profile = ReaderProfile()
        #expect(profile.name == "Reader")
        #expect(profile.avatarSymbol == "person.crop.circle.fill")
        #expect(profile.colorName == "accent")
        #expect(profile.voiceIdentifier.isEmpty)
        #expect(profile.speechRate == 0.45)
        #expect(profile.fontSize == 22)
        #expect(profile.readerTheme == "piperly")
        #expect(!profile.hasCompletedVoiceSetup)
    }

    @Test func codableRoundTrip() throws {
        let profile = try ReaderProfile(
            name: "Ari",
            avatarSymbol: "star.fill",
            colorName: "yellow",
            voiceIdentifier: "voice.ari",
            speechRate: 0.55,
            fontSize: 27,
            readerTheme: "ocean",
            hasCompletedVoiceSetup: true
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ReaderProfile.self, from: data)
        #expect(decoded.id == profile.id)
        #expect(decoded.name == "Ari")
        #expect(decoded.avatarSymbol == "star.fill")
        #expect(decoded.colorName == "yellow")
        #expect(decoded.voiceIdentifier == "voice.ari")
        #expect(decoded.speechRate == 0.55)
        #expect(decoded.fontSize == 27)
        #expect(decoded.readerTheme == "ocean")
        #expect(decoded.hasCompletedVoiceSetup)
    }

    @Test func decodingOlderProfileUsesPreferenceDefaults() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let legacyJSON = """
        {
          "id": "\(id.uuidString)",
          "name": "Ari",
          "avatarSymbol": "star.fill",
          "colorName": "yellow",
          "createdAt": \(createdAt.timeIntervalSinceReferenceDate)
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let decoded = try decoder.decode(ReaderProfile.self, from: Data(legacyJSON.utf8))
        #expect(decoded.voiceIdentifier.isEmpty)
        #expect(decoded.speechRate == ReaderProfile.defaultSpeechRate)
        #expect(decoded.fontSize == ReaderProfile.defaultFontSize)
        #expect(decoded.readerTheme == ReaderProfile.defaultReaderTheme)
        #expect(!decoded.hasCompletedVoiceSetup)
    }

    // A name that was valid under the old sanitizer (spaces/digits allowed) must
    // survive decode by being sanitized, not throw and wipe the profiles array.
    @Test func decodingLegacyInvalidNicknameSanitizesInsteadOfThrowing() throws {
        let id = UUID()
        let legacyJSON = """
        {
          "id": "\(id.uuidString)",
          "name": "Ari Smith12",
          "avatarSymbol": "star.fill",
          "colorName": "yellow",
          "createdAt": 0
        }
        """
        let decoded = try JSONDecoder().decode(ReaderProfile.self, from: Data(legacyJSON.utf8))
        #expect(decoded.id == id)
        #expect(decoded.name == "AriSmith")
    }

    @Test func rejectsInvalidNicknames() {
        #expect(throws: ReaderProfile.NicknameValidationError.empty) {
            _ = try ReaderProfile(name: "   ")
        }
        #expect(throws: ReaderProfile.NicknameValidationError.containsWhitespace) {
            _ = try ReaderProfile(name: "Ari Smith")
        }
        #expect(throws: ReaderProfile.NicknameValidationError.containsDigits) {
            _ = try ReaderProfile(name: "Ari12")
        }
        #expect(throws: ReaderProfile.NicknameValidationError.containsAccountIdentifier) {
            _ = try ReaderProfile(name: "ari@example.com")
        }
    }
}

// MARK: - Reader Profile Preferences

@Suite("ReaderProfilePreferences", .serialized)
struct ReaderProfilePreferenceTests {
    @Test @MainActor func switchingProfilesChangesActivePreferences() throws {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstProfileID = store.activeProfile.id
        store.updateActiveProfile {
            $0.voiceIdentifier = "voice.first"
            $0.fontSize = 24
        }
        let secondProfile = try store.addProfile(
            name: "Bee",
            avatarSymbol: "star.fill",
            colorName: "green"
        )

        #expect(store.activeProfile.id == secondProfile.id)
        #expect(store.activeVoiceIdentifier.isEmpty)
        #expect(store.activeFontSize == ReaderProfile.defaultFontSize)

        store.selectProfile(firstProfileID)
        #expect(store.activeVoiceIdentifier == "voice.first")
        #expect(store.activeFontSize == 24)
    }

    @Test @MainActor func preferencesStayIsolatedBetweenProfiles() throws {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstProfileID = store.activeProfile.id
        store.updateActiveProfile {
            $0.voiceIdentifier = "voice.first"
            $0.speechRate = 0.35
            $0.fontSize = 19
            $0.readerTheme = "forest"
            $0.hasCompletedVoiceSetup = true
        }
        let secondProfile = try store.addProfile(
            name: "Bee",
            avatarSymbol: "moon.fill",
            colorName: "info"
        )
        store.updateActiveProfile {
            $0.voiceIdentifier = "voice.second"
            $0.speechRate = 0.60
            $0.fontSize = 30
            $0.readerTheme = "nightOwl"
        }

        store.selectProfile(firstProfileID)
        #expect(store.activeProfile.voiceIdentifier == "voice.first")
        #expect(store.activeProfile.speechRate == 0.35)
        #expect(store.activeProfile.fontSize == 19)
        #expect(store.activeProfile.readerTheme == "forest")
        #expect(store.activeProfile.hasCompletedVoiceSetup)

        store.selectProfile(secondProfile.id)
        #expect(store.activeProfile.voiceIdentifier == "voice.second")
        #expect(store.activeProfile.speechRate == 0.60)
        #expect(store.activeProfile.fontSize == 30)
        #expect(store.activeProfile.readerTheme == "nightOwl")
        #expect(!store.activeProfile.hasCompletedVoiceSetup)
    }

    @Test @MainActor func preferencesPersistAcrossStoreReload() throws {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.updateActiveProfile {
            $0.voiceIdentifier = "voice.persisted"
            $0.speechRate = 0.50
            $0.fontSize = 26
            $0.readerTheme = "lavender"
            $0.hasCompletedVoiceSetup = true
        }

        let reloadedStore = BookStore(userDefaults: defaults)
        #expect(reloadedStore.activeProfile.id == store.activeProfile.id)
        #expect(reloadedStore.activeVoiceIdentifier == "voice.persisted")
        #expect(reloadedStore.activeSpeechRate == 0.50)
        #expect(reloadedStore.activeFontSize == 26)
        #expect(reloadedStore.activeReaderTheme == .lavender)
        #expect(reloadedStore.activeProfile.hasCompletedVoiceSetup)
    }

    @Test @MainActor func serviceRejectsInvalidNicknameWithoutRemovingDefault() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(throws: ReaderProfile.NicknameValidationError.containsWhitespace) {
            _ = try store.addProfile(
                name: "Ari Smith",
                avatarSymbol: "star.fill",
                colorName: "green"
            )
        }
        #expect(store.profiles.count == 1)
        #expect(store.activeProfile.name == ReaderProfile.defaultName)

        #expect(throws: ReaderProfile.NicknameValidationError.containsDigits) {
            try store.updateProfile(
                store.activeProfile.id,
                name: "Reader2",
                avatarSymbol: "star.fill",
                colorName: "green"
            )
        }
        #expect(store.activeProfile.name == ReaderProfile.defaultName)
    }

    @MainActor
    private func makeStore() -> (BookStore, UserDefaults, String) {
        let suiteName = "PiperlyTests.ReaderProfilePreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (BookStore(userDefaults: defaults), defaults, suiteName)
    }
}

// MARK: - ReadingState

@Suite("ReadingState")
struct ReadingStateTests {
    @Test func defaultValues() {
        let state = ReadingState(profileID: UUID(), bookID: UUID())
        #expect(state.lastReadProgression == 0)
        #expect(state.lastReadLocatorJSON == nil)
    }

    @Test func codableRoundTrip() throws {
        let state = ReadingState(
            profileID: UUID(),
            bookID: UUID(),
            lastReadProgression: 0.42,
            lastReadLocatorJSON: "{\"href\":\"/chapter\"}"
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReadingState.self, from: data)
        #expect(decoded.id == state.id)
        #expect(decoded.profileID == state.profileID)
        #expect(decoded.bookID == state.bookID)
        #expect(decoded.lastReadProgression == 0.42)
        #expect(decoded.lastReadLocatorJSON == "{\"href\":\"/chapter\"}")
    }
}

// MARK: - ReaderTheme

@Suite("ReaderTheme")
struct ReaderThemeTests {
    @Test func allCasesCount() {
        #expect(ReaderTheme.allCases.count == 7)
    }

    @Test func isDarkThemes() {
        #expect(ReaderTheme.piperly.isDark == true)
        #expect(ReaderTheme.nightOwl.isDark == true)
        #expect(ReaderTheme.sunshine.isDark == false)
        #expect(ReaderTheme.ocean.isDark == false)
        #expect(ReaderTheme.forest.isDark == false)
        #expect(ReaderTheme.lavender.isDark == false)
        #expect(ReaderTheme.cozy.isDark == false)
    }

    @Test func highlightColorComputation() {
        // piperly textColor is #E8E8F0 -> R=232, G=232, B=240
        #expect(ReaderTheme.piperly.highlightColor == "rgba(232, 232, 240, 0.3)")
    }

    @Test func cssVariablesScriptContainsAllVars() {
        let script = ReaderTheme.piperly.cssVariablesScript
        #expect(script.contains("--piperly-bg"))
        #expect(script.contains("--piperly-text"))
        #expect(script.contains("--piperly-accent"))
        #expect(script.contains("--piperly-highlight"))
    }

    @Test func cssVariablesScriptContainsColors() {
        let script = ReaderTheme.piperly.cssVariablesScript
        #expect(script.contains(ReaderTheme.piperly.backgroundColor))
        #expect(script.contains(ReaderTheme.piperly.textColor))
    }

    @Test func fontFamilyMapping() {
        #expect(ReaderTheme.piperly.fontFamily == .sansSerif)
        #expect(ReaderTheme.sunshine.fontFamily == .sansSerif)
        #expect(ReaderTheme.ocean.fontFamily == .sansSerif)
        #expect(ReaderTheme.lavender.fontFamily == .sansSerif)
        #expect(ReaderTheme.forest.fontFamily == .serif)
        #expect(ReaderTheme.nightOwl.fontFamily == .serif)
        #expect(ReaderTheme.cozy.fontFamily == .serif)
    }

    @Test func rawValueRoundTrip() {
        #expect(ReaderTheme(rawValue: "piperly") == .piperly)
        #expect(ReaderTheme(rawValue: "nightOwl") == .nightOwl)
        #expect(ReaderTheme(rawValue: "nonexistent") == nil)
    }
}

// MARK: - Voice

@Suite("Voice")
struct VoiceTests {
    @Test func qualitySortOrder() {
        #expect(Voice.Quality.premium < Voice.Quality.enhanced)
        #expect(Voice.Quality.enhanced < Voice.Quality.standard)
        #expect(Voice.Quality.premium < Voice.Quality.standard)
    }

    @Test func qualityRawValues() {
        #expect(Voice.Quality.premium.rawValue == "Premium")
        #expect(Voice.Quality.enhanced.rawValue == "Enhanced")
        #expect(Voice.Quality.standard.rawValue == "Standard")
    }

    @Test func stableHashIsDeterministic() {
        // "Samantha" UTF-8 byte sum: 83+97+109+97+110+116+104+97
        #expect(Voice.stableHash("Samantha") == 813)
        #expect(Voice.stableHash("Samantha") == Voice.stableHash("Samantha"))
        #expect(Voice.stableHash("") == 0)
    }

    @Test func colorIsStableForSameName() {
        let first = Voice(id: "a", name: "Samantha", language: "en-US", quality: .premium)
        let second = Voice(id: "b", name: "Samantha", language: "en-GB", quality: .standard)
        #expect(first.color == second.color)
    }
}

// MARK: - BookStore Import (INT-344)

@Suite("BookStoreImport")
struct BookStoreImportTests {
    @Test func uniqueFileNamePreservesOriginalName() {
        let name = BookStore.uniqueFileName(for: "alice.epub")
        #expect(name.hasSuffix("-alice.epub"))
    }

    @Test func uniqueFileNameDiffersForSameSource() {
        let first = BookStore.uniqueFileName(for: "alice.epub")
        let second = BookStore.uniqueFileName(for: "alice.epub")
        #expect(first != second)
    }

    @Test func uniqueFileNameHasUUIDPrefix() {
        let name = BookStore.uniqueFileName(for: "alice.epub")
        let prefix = name.replacingOccurrences(of: "-alice.epub", with: "")
        #expect(UUID(uuidString: prefix) != nil)
    }

    @Test @MainActor func rejectsUnreadableEPUBWithoutAddingBook() async throws {
        let store = BookStore()
        let sourceName = "garbage-\(UUID().uuidString).epub"
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(sourceName)
        try Data("not an epub".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let countBefore = store.books.count
        await #expect(throws: BookStoreError.self) {
            _ = try await store.importBook(from: sourceURL)
        }
        #expect(store.books.count == countBefore)

        let booksDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Books", isDirectory: true)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: booksDir.path)) ?? []
        #expect(!leftovers.contains { $0.hasSuffix(sourceName) })
    }
}

// MARK: - WordTap (INT-343)

@Suite("WordTap")
struct WordTapTests {
    @Test func sameWordProducesDistinctTaps() {
        let first = WordTap(word: "cat")
        let second = WordTap(word: "cat")
        #expect(first.word == second.word)
        #expect(first != second)
        #expect(first.id != second.id)
    }

    @Test func tapEqualsItself() {
        let tap = WordTap(word: "dog")
        #expect(tap == tap)
    }
}
