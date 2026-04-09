import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var bookStore: BookStore
    @Binding var selectedBook: Book?
    @Binding var showingImporter: Bool
    @State private var bookToDelete: Book?
    @State private var showingDeleteConfirmation = false

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
                            BookCard(book: book) {
                                bookToDelete = book
                                showingDeleteConfirmation = true
                            }
                            .onTapGesture { selectedBook = book }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .overlay {
            if showingDeleteConfirmation, let book = bookToDelete {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingDeleteConfirmation = false
                        bookToDelete = nil
                    }

                VStack(spacing: 20) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 44))
                        .foregroundStyle(Piperly.Colors.error)

                    Text("Remove this book?")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Piperly.Colors.textPrimary)

                    Text("\"\(book.title)\" will be removed from your library.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(Piperly.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    HStack(spacing: 16) {
                        Button {
                            showingDeleteConfirmation = false
                            bookToDelete = nil
                        } label: {
                            Label("Keep it", systemImage: "heart.fill")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Piperly.Colors.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Piperly.Colors.accent.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        Button {
                            bookStore.deleteBook(book)
                            showingDeleteConfirmation = false
                            bookToDelete = nil
                        } label: {
                            Label("Remove", systemImage: "trash.fill")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Piperly.Colors.error)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Piperly.Colors.error.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 340)
                .background(Piperly.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Piperly.Colors.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: showingDeleteConfirmation)
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
