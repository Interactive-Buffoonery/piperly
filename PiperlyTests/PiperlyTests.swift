import Testing
@testable import Piperly

@Test func bookModelCreation() async throws {
    let book = Book(title: "Test Book", author: "Test Author", fileName: "test.epub")
    #expect(book.title == "Test Book")
    #expect(book.author == "Test Author")
    #expect(book.lastReadProgression == 0.0)
}

@Test func voiceCuratedList() async throws {
    let voices = Voice.curated
    #expect(voices.count == 7)
    #expect(voices[0].name == "Heart")
    #expect(voices[0].id == 3)
}
