import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bookStore: BookStore
    @State private var selectedBook: Book?

    let ttsEngine: TTSEngine

    var body: some View {
        NavigationStack {
            LibraryView(selectedBook: $selectedBook)
                .fullScreenCover(item: $selectedBook) { book in
                    ReaderView(book: book, ttsEngine: ttsEngine)
                        .environmentObject(bookStore)
                }
        }
    }
}
