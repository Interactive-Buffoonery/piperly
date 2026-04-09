import Testing
import Foundation
@testable import Piperly

// MARK: - Book

@Suite("Book")
struct BookTests {
    @Test func defaultValues() {
        let book = Book(title: "Test", author: "Author", fileName: "test.epub")
        #expect(book.lastReadProgression == 0.0)
        #expect(book.lastReadLocatorJSON == nil)
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
        #expect(decoded.lastReadProgression == book.lastReadProgression)
    }

    @Test func codableWithAllFields() throws {
        let book = Book(
            title: "Test",
            author: "Author",
            fileName: "test.epub",
            coverImageName: "cover.jpg",
            lastReadProgression: 0.75,
            lastReadLocatorJSON: "{\"href\":\"/ch1\"}"
        )
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(Book.self, from: data)
        #expect(decoded.coverImageName == "cover.jpg")
        #expect(decoded.lastReadProgression == 0.75)
        #expect(decoded.lastReadLocatorJSON == "{\"href\":\"/ch1\"}")
    }
}

// MARK: - Bookmark

@Suite("Bookmark")
struct BookmarkTests {
    @Test func defaultValues() {
        let now = Date.now
        let bookmark = Bookmark(
            bookID: UUID(),
            locatorJSON: "{}",
            title: "Chapter 1",
            progression: 0.5,
            sticker: .star
        )
        #expect(bookmark.title == "Chapter 1")
        #expect(bookmark.progression == 0.5)
        #expect(bookmark.sticker == .star)
        #expect(bookmark.createdAt.timeIntervalSince(now) < 1)
    }

    @Test func codableRoundTrip() throws {
        let bookmark = Bookmark(
            bookID: UUID(),
            locatorJSON: "{\"href\":\"/ch2\"}",
            title: "Chapter 2",
            progression: 0.33,
            sticker: .heart
        )
        let data = try JSONEncoder().encode(bookmark)
        let decoded = try JSONDecoder().decode(Bookmark.self, from: data)
        #expect(decoded.id == bookmark.id)
        #expect(decoded.bookID == bookmark.bookID)
        #expect(decoded.locatorJSON == bookmark.locatorJSON)
        #expect(decoded.title == bookmark.title)
        #expect(decoded.progression == bookmark.progression)
        #expect(decoded.sticker == bookmark.sticker)
    }

    @Test func allStickersSurviveCoding() throws {
        for sticker in BookmarkSticker.allCases {
            let bookmark = Bookmark(
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
        let word = SavedWord(
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
    }

    @Test func codableRoundTrip() throws {
        let word = SavedWord(
            word: "mysterious",
            displayWord: "Mysterious",
            bookID: UUID(),
            bookTitle: "The Secret Garden",
            tapCount: 3
        )
        let data = try JSONEncoder().encode(word)
        let decoded = try JSONDecoder().decode(SavedWord.self, from: data)
        #expect(decoded.id == word.id)
        #expect(decoded.word == word.word)
        #expect(decoded.displayWord == word.displayWord)
        #expect(decoded.bookID == word.bookID)
        #expect(decoded.bookTitle == word.bookTitle)
        #expect(decoded.tapCount == 3)
    }
}

// MARK: - CatalogItem

@Suite("CatalogItem")
struct CatalogItemTests {
    @Test func propertiesWithAndWithoutOptionals() {
        let full = CatalogItem(
            id: "item-1",
            title: "Alice in Wonderland",
            author: "Lewis Carroll",
            description: "A classic tale",
            coverURL: URL(string: "https://example.com/cover.jpg"),
            acquisitionURL: URL(string: "https://example.com/book.epub"),
            mediaType: "application/epub+zip"
        )
        #expect(full.title == "Alice in Wonderland")
        #expect(full.author == "Lewis Carroll")
        #expect(full.mediaType == "application/epub+zip")

        let minimal = CatalogItem(
            id: "item-2",
            title: "Untitled",
            author: nil,
            description: nil,
            coverURL: nil,
            acquisitionURL: nil,
            mediaType: nil
        )
        #expect(minimal.author == nil)
        #expect(minimal.coverURL == nil)
        #expect(minimal.acquisitionURL == nil)
    }
}

// MARK: - OPDSServerConfig

@Suite("OPDSServerConfig")
struct OPDSServerConfigTests {
    @Test func authHeaderBasicEncoding() {
        let config = OPDSServerConfig(
            url: URL(string: "https://example.com")!,
            username: "admin",
            password: "secret"
        )
        #expect(config.authorizationHeaderValue() == "Basic YWRtaW46c2VjcmV0")
    }

    @Test func authHeaderEmptyUsernameReturnsNil() {
        let config = OPDSServerConfig(
            url: URL(string: "https://example.com")!,
            username: "",
            password: "secret"
        )
        #expect(config.authorizationHeaderValue() == nil)
    }

    @Test func authHeaderEmptyPasswordStillWorks() {
        let config = OPDSServerConfig(
            url: URL(string: "https://example.com")!,
            username: "user",
            password: ""
        )
        #expect(config.authorizationHeaderValue() == "Basic dXNlcjo=")
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
}

// MARK: - DownloadProgress

@Suite("DownloadProgress")
struct DownloadProgressTests {
    @Test func fractionWithKnownTotal() {
        let progress = DownloadProgress(bytesReceived: 50, totalBytes: 100)
        #expect(progress.fraction == 0.5)
    }

    @Test func fractionWithUnknownTotal() {
        let progress = DownloadProgress(bytesReceived: 50, totalBytes: nil)
        #expect(progress.fraction == 0)
    }

    @Test func fractionWithZeroTotal() {
        let progress = DownloadProgress(bytesReceived: 0, totalBytes: 0)
        #expect(progress.fraction == 0)
    }
}

// MARK: - OPDSError

@Suite("OPDSError")
struct OPDSErrorTests {
    @Test func allCasesHaveFriendlyMessages() {
        let cases: [OPDSError] = [
            .notConfigured,
            .connectionFailed,
            .feedParsingFailed,
            .downloadFailed("test"),
            .noAcquisitionLink,
        ]
        for error in cases {
            #expect(!error.friendlyMessage.isEmpty)
        }
    }
}
