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

struct CatalogDetailSheet: View {
    let item: CatalogItem
    let isAlreadyDownloaded: Bool
    let onDownload: () -> Void
    var onOpenBook: (() -> Void)?

    @EnvironmentObject var opdsService: OPDSService
    @EnvironmentObject var bookStore: BookStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var imageLoader = AuthenticatedImageLoader()
    @State private var justDownloaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Cover
                    if let image = imageLoader.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Piperly.Colors.surfaceElevated)
                            .frame(width: 200, height: 300)
                            .overlay {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 48))
                                    .foregroundStyle(Piperly.Colors.textTertiary)
                            }
                    }

                    // Title + Author
                    VStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Piperly.Colors.textPrimary)
                            .multilineTextAlignment(.center)

                        if let author = item.author {
                            Text(author)
                                .font(Piperly.Typography.body)
                                .foregroundStyle(Piperly.Colors.textSecondary)
                        }
                    }

                    // Download / Read button
                    if isAlreadyDownloaded || justDownloaded {
                        VStack(spacing: 12) {
                            Label("In Your Library", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(Piperly.Colors.success)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(Piperly.Colors.success.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 16))

                            if onOpenBook != nil {
                                Button {
                                    dismiss()
                                    onOpenBook?()
                                } label: {
                                    Label("Read Now", systemImage: "book.fill")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 32)
                                        .padding(.vertical, 14)
                                        .background(Piperly.Colors.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                            }
                        }
                    } else if let progress = opdsService.activeDownloads[item.id] {
                        VStack(spacing: 8) {
                            ProgressView(value: progress.fraction)
                                .tint(Piperly.Colors.accent)
                                .frame(width: 200)
                            Text("Downloading...")
                                .font(Piperly.Typography.caption)
                                .foregroundStyle(Piperly.Colors.textSecondary)
                        }
                    } else if item.acquisitionURL != nil {
                        Button {
                            onDownload()
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(Piperly.Colors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }

                    // Description
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(Piperly.Typography.body)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(24)
            }
            .background(Piperly.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Piperly.Colors.accent)
                }
            }
            .toolbarBackground(Piperly.Colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Piperly.Colors.background)
        .task {
            if let coverURL = item.coverURL {
                await imageLoader.load(url: coverURL)
            }
        }
        .onChange(of: bookStore.books.count) {
            if !isAlreadyDownloaded && bookStore.books.contains(where: {
                $0.title.localizedCaseInsensitiveCompare(item.title) == .orderedSame
            }) {
                justDownloaded = true
            }
        }
    }
}
