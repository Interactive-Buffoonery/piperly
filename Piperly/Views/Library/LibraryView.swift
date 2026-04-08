import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var bookStore: BookStore
    @Binding var selectedBook: Book?
    @Binding var showingImporter: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 24)
    ]

    var body: some View {
        ZStack {
            Piperly.Colors.background.ignoresSafeArea()

            if bookStore.books.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(bookStore.books) { book in
                            BookCard(book: book)
                                .onTapGesture { selectedBook = book }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        bookStore.deleteBook(book)
                                    } label: {
                                        Label("Delete Book", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                _ = try? await bookStore.importBook(from: url)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(Piperly.Colors.textTertiary)
            Text("No books yet")
                .font(Piperly.Typography.title)
                .foregroundStyle(Piperly.Colors.textPrimary)
            Text("Tap + to import an EPUB")
                .font(Piperly.Typography.body)
                .foregroundStyle(Piperly.Colors.textSecondary)
            Button {
                showingImporter = true
            } label: {
                Label("Add Book", systemImage: "plus")
                    .font(Piperly.Typography.body)
                    .foregroundStyle(Piperly.Colors.accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Piperly.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
