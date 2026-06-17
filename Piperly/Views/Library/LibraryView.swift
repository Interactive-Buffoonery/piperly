// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var bookStore: BookStore
    @Binding var selectedBook: Book?
    @Binding var showingImporter: Bool
    @State private var bookToDelete: Book?
    @State private var showingDeleteConfirmation = false
    @State private var importErrorMessage: String?

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
                            BookCard(
                                book: book,
                                coverImage: bookStore.coverImage(for: book)
                            ) {
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
        .task {
            await bookStore.backfillCovers()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    do {
                        _ = try await bookStore.importBook(from: url)
                    } catch {
                        importErrorMessage = "Couldn't add that book. Please try a different EPUB file."
                    }
                }
            case .failure:
                importErrorMessage = "Couldn't add that book. Please try a different EPUB file."
            }
        }
        .alert("Import Failed", isPresented: importErrorBinding, presenting: importErrorMessage) { _ in
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )
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
