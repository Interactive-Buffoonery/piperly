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

struct BookCard: View {
    let book: Book
    var progress: Double
    var coverImage: UIImage?
    var availability: BookAssetAvailability = .local
    var onDelete: (() -> Void)?
    @State private var showingMenu = false

    private var assetBadge: (symbol: String, tint: Color)? {
        switch availability {
        case .local:
            return nil
        case .downloading, .uploading:
            return ("arrow.triangle.2.circlepath.icloud", Piperly.Colors.accent)
        case .remoteOnly:
            return ("icloud.and.arrow.down", Piperly.Colors.accent)
        case .retryableFailure:
            return ("exclamationmark.icloud", Piperly.Colors.accent)
        case .unavailable:
            return ("xmark.icloud", Piperly.Colors.error)
        }
    }

    private var availabilityAccessibilityLabel: String {
        switch availability {
        case .local: return ""
        case .downloading, .uploading: return "Syncing from iCloud"
        case .remoteOnly: return "Stored in iCloud, tap to download"
        case .retryableFailure: return "Download failed, tap to retry"
        case .unavailable: return "This book is unavailable"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover
            ZStack(alignment: .topTrailing) {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(0.65, contentMode: .fill)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Piperly.Colors.surfaceElevated)
                        .aspectRatio(0.65, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Piperly.Colors.textTertiary)
                                Text(book.title)
                                    .font(Piperly.Typography.caption)
                                    .foregroundStyle(Piperly.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .padding(.horizontal, 8)
                            }
                        }
                }

                if onDelete != nil {
                    Button { showingMenu.toggle() } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding(6)
                }

                if let assetBadge {
                    Image(systemName: assetBadge.symbol)
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(assetBadge.tint, .black.opacity(0.5))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .accessibilityLabel(availabilityAccessibilityLabel)
                }
            }

            // Title
            Text(book.title)
                .font(Piperly.Typography.caption)
                .foregroundStyle(Piperly.Colors.textPrimary)
                .lineLimit(1)

            // Author
            Text(book.author)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Piperly.Colors.textSecondary)
                .lineLimit(1)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Piperly.Colors.border)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Piperly.Colors.accent)
                        .frame(width: geo.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .background(Piperly.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Piperly.Colors.border, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if showingMenu {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        showingMenu = false
                        onDelete?()
                    } label: {
                        Label("Remove Book", systemImage: "trash")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Piperly.Colors.error)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Piperly.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Piperly.Colors.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                .frame(width: 180)
                .padding(.top, 40)
                .padding(.trailing, 4)
                .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.2), value: showingMenu)
        .zIndex(showingMenu ? 1 : 0)
    }
}
