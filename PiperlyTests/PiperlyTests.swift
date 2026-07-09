import Testing
import Foundation
@testable import Piperly

// MARK: - Book

@Suite("Book")
struct BookTests {
    @Test func defaultValues() {
        let book = Book(
            contentIdentity: "abc123",
            title: "Test",
            author: "Author",
            fileName: "test.epub"
        )
        #expect(book.coverImageName == nil)
    }

    @Test func codableRoundTrip() throws {
        let book = Book(
            contentIdentity: "abc123",
            title: "The Secret Garden",
            author: "Frances Hodgson Burnett",
            fileName: "secret-garden.epub"
        )
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(Book.self, from: data)
        #expect(decoded.id == book.id)
        #expect(decoded.contentIdentity == book.contentIdentity)
        #expect(decoded.title == book.title)
        #expect(decoded.author == book.author)
        #expect(decoded.fileName == book.fileName)
    }

    @Test func codableWithAllFields() throws {
        let book = Book(
            contentIdentity: "abc123",
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
    @Test @MainActor func startupClearsStaleImportSnapshots() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-stale-snapshots-\(UUID().uuidString)", isDirectory: true)
        let booksDirectory = rootURL.appendingPathComponent("Books", isDirectory: true)
        let coversDirectory = rootURL.appendingPathComponent("Covers", isDirectory: true)
        let snapshotsDirectory = rootURL.appendingPathComponent(".PiperlyImportSnapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        try Data("stale epub bytes".utf8).write(
            to: snapshotsDirectory.appendingPathComponent("stale.epub")
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let defaultsName = "PiperlyTests.BookStoreStartupCleanup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        _ = BookStore(
            documentsURL: booksDirectory,
            coversURL: coversDirectory,
            userDefaults: defaults
        )

        #expect(FileManager.default.fileExists(atPath: snapshotsDirectory.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: snapshotsDirectory.path).isEmpty)
    }

    @Test func sameBytesProduceSameIdentity() throws {
        let firstURL = try temporaryFile(containing: Data("same bytes".utf8))
        let secondURL = try temporaryFile(containing: Data("same bytes".utf8))
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        #expect(try BookStore.contentIdentity(for: firstURL) == BookStore.contentIdentity(for: secondURL))
    }

    @Test func differentBytesProduceDifferentIdentities() throws {
        let firstURL = try temporaryFile(containing: Data("first".utf8))
        let secondURL = try temporaryFile(containing: Data("second".utf8))
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        #expect(try BookStore.contentIdentity(for: firstURL) != BookStore.contentIdentity(for: secondURL))
    }

    @Test func identityIncludesBytesBeyondFirstReadChunk() throws {
        let prefix = Data(repeating: 0x41, count: 1_048_576)
        let firstURL = try temporaryFile(containing: prefix + Data([0x42]))
        let secondURL = try temporaryFile(containing: prefix + Data([0x43]))
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        #expect(try BookStore.contentIdentity(for: firstURL) != BookStore.contentIdentity(for: secondURL))
    }

    @Test func identityIsDeterministicLowercaseHex() throws {
        let fileURL = try temporaryFile(containing: Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let identity = try BookStore.contentIdentity(for: fileURL)
        #expect(identity == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(identity.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(BookStore.storageFileName(for: identity) == "\(identity).epub")
    }

    @Test @MainActor func rejectsUnreadableEPUBWithoutAddingBook() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-unreadable-\(UUID().uuidString)", isDirectory: true)
        let booksDirectory = rootURL.appendingPathComponent("Books", isDirectory: true)
        let coversDirectory = rootURL.appendingPathComponent("Covers", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let defaultsName = "PiperlyTests.BookStoreUnreadable.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = BookStore(
            documentsURL: booksDirectory,
            coversURL: coversDirectory,
            userDefaults: defaults
        )

        let sourceURL = rootURL.appendingPathComponent("garbage.epub")
        try Data("not an epub".utf8).write(to: sourceURL)
        let expectedStoredName = BookStore.storageFileName(for: try BookStore.contentIdentity(for: sourceURL))
        let contentsBefore = try FileManager.default.contentsOfDirectory(atPath: booksDirectory.path)

        await #expect(throws: BookStoreError.self) {
            _ = try await store.importBook(from: sourceURL)
        }
        #expect(store.books.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: booksDirectory.path) == contentsBefore)
        #expect(!FileManager.default.fileExists(
            atPath: booksDirectory.appendingPathComponent(expectedStoredName).path
        ))
        let snapshotsDirectory = rootURL.appendingPathComponent(".PiperlyImportSnapshots", isDirectory: true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: snapshotsDirectory.path).isEmpty)
    }

    @Test @MainActor func duplicateImportReturnsExistingBookWithoutExtraFilesOrMetadata() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-import-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let booksDirectory = rootURL.appendingPathComponent("Books", isDirectory: true)
        let coversDirectory = rootURL.appendingPathComponent("Covers", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let defaultsName = "PiperlyTests.BookStoreImport.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = BookStore(
            documentsURL: booksDirectory,
            coversURL: coversDirectory,
            userDefaults: defaults
        )

        let bundledBook = try #require(Bundle.main.url(forResource: "the-secret-garden", withExtension: "epub"))
        let firstSource = sourceDirectory.appendingPathComponent("first.epub")
        let secondSource = sourceDirectory.appendingPathComponent("renamed.epub")
        try FileManager.default.copyItem(at: bundledBook, to: firstSource)
        try FileManager.default.copyItem(at: bundledBook, to: secondSource)

        let first = try await store.importBook(from: firstSource)
        let second = try await store.importBook(from: secondSource)

        #expect(first.id == second.id)
        #expect(first.contentIdentity == second.contentIdentity)
        #expect(store.books.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: booksDirectory.path) == [first.fileName])
        let coverFiles = try FileManager.default.contentsOfDirectory(atPath: coversDirectory.path)
        #expect(coverFiles.count <= 1)
    }

    @Test @MainActor func reimportRestoresMissingDeterministicFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-repair-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let booksDirectory = rootURL.appendingPathComponent("Books", isDirectory: true)
        let coversDirectory = rootURL.appendingPathComponent("Covers", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let defaultsName = "PiperlyTests.BookStoreRepair.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = BookStore(
            documentsURL: booksDirectory,
            coversURL: coversDirectory,
            userDefaults: defaults
        )

        let bundledBook = try #require(Bundle.main.url(forResource: "the-secret-garden", withExtension: "epub"))
        let firstSource = sourceDirectory.appendingPathComponent("first.epub")
        let secondSource = sourceDirectory.appendingPathComponent("second.epub")
        try FileManager.default.copyItem(at: bundledBook, to: firstSource)
        try FileManager.default.copyItem(at: bundledBook, to: secondSource)

        let original = try await store.importBook(from: firstSource)
        let storedURL = store.bookURL(for: original)
        try FileManager.default.removeItem(at: storedURL)
        #expect(!FileManager.default.fileExists(atPath: storedURL.path))

        let repaired = try await store.importBook(from: secondSource)

        #expect(repaired.id == original.id)
        #expect(store.books.count == 1)
        #expect(FileManager.default.fileExists(atPath: storedURL.path))
        #expect(try Data(contentsOf: storedURL) == Data(contentsOf: bundledBook))
    }

    @Test @MainActor func concurrentSameContentImportsPublishOneBookAndFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-concurrent-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let booksDirectory = rootURL.appendingPathComponent("Books", isDirectory: true)
        let coversDirectory = rootURL.appendingPathComponent("Covers", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let defaultsName = "PiperlyTests.BookStoreConcurrent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = BookStore(
            documentsURL: booksDirectory,
            coversURL: coversDirectory,
            userDefaults: defaults
        )

        let bundledBook = try #require(Bundle.main.url(forResource: "the-secret-garden", withExtension: "epub"))
        let firstSource = sourceDirectory.appendingPathComponent("first.epub")
        let secondSource = sourceDirectory.appendingPathComponent("second.epub")
        try FileManager.default.copyItem(at: bundledBook, to: firstSource)
        try FileManager.default.copyItem(at: bundledBook, to: secondSource)

        async let first = store.importBook(from: firstSource)
        async let second = store.importBook(from: secondSource)
        let (firstBook, secondBook) = try await (first, second)

        #expect(firstBook.id == secondBook.id)
        #expect(store.books.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: booksDirectory.path) == [firstBook.fileName])
        let snapshotsDirectory = rootURL.appendingPathComponent(".PiperlyImportSnapshots", isDirectory: true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: snapshotsDirectory.path).isEmpty)
    }

    @Test @MainActor func matchingIdentityNeverOverwritesDifferentStoredBytes() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("piperly-collision-\(UUID().uuidString)", isDirectory: true)
        let booksDirectory = rootURL.appendingPathComponent("Books", isDirectory: true)
        let coversDirectory = rootURL.appendingPathComponent("Covers", isDirectory: true)
        try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let defaultsName = "PiperlyTests.BookStoreCollision.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = BookStore(
            documentsURL: booksDirectory,
            coversURL: coversDirectory,
            userDefaults: defaults
        )

        let sourceURL = rootURL.appendingPathComponent("source.epub")
        let sourceBytes = Data("source bytes".utf8)
        try sourceBytes.write(to: sourceURL)
        let identity = try BookStore.contentIdentity(for: sourceURL)
        let storedName = BookStore.storageFileName(for: identity)
        let storedURL = booksDirectory.appendingPathComponent(storedName)
        let storedBytes = Data("different stored bytes".utf8)
        try storedBytes.write(to: storedURL)
        store.books = [Book(
            contentIdentity: identity,
            title: "Existing",
            author: "Author",
            fileName: storedName
        )]

        await #expect(throws: BookStoreError.self) {
            _ = try await store.importBook(from: sourceURL)
        }
        #expect(try Data(contentsOf: storedURL) == storedBytes)
        #expect(store.books.count == 1)
    }

    private func temporaryFile(containing data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
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
