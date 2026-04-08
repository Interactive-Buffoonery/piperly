import SwiftUI

struct CatalogBookCard: View {
    let item: CatalogItem
    let downloadProgress: DownloadProgress?
    let isAlreadyDownloaded: Bool

    @StateObject private var imageLoader = AuthenticatedImageLoader()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover
            RoundedRectangle(cornerRadius: 8)
                .fill(Piperly.Colors.surfaceElevated)
                .aspectRatio(0.65, contentMode: .fit)
                .overlay {
                    if let image = imageLoader.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if imageLoader.isLoading {
                        ProgressView()
                            .tint(Piperly.Colors.textTertiary)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 36))
                                .foregroundStyle(Piperly.Colors.textTertiary)
                            Text(item.title)
                                .font(Piperly.Typography.caption)
                                .foregroundStyle(Piperly.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    statusBadge
                        .padding(6)
                }

            Text(item.title)
                .font(Piperly.Typography.caption)
                .foregroundStyle(Piperly.Colors.textPrimary)
                .lineLimit(1)

            if let author = item.author {
                Text(author)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Piperly.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Piperly.Colors.border, lineWidth: 1)
        )
        .task {
            if let coverURL = item.coverURL {
                await imageLoader.load(url: coverURL)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isAlreadyDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Piperly.Colors.success)
                .background(Circle().fill(Piperly.Colors.surface))
        } else if let progress = downloadProgress {
            ZStack {
                Circle()
                    .fill(Piperly.Colors.surface)
                    .frame(width: 28, height: 28)
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(Piperly.Colors.accent, lineWidth: 3)
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(-90))
            }
        } else if item.acquisitionURL != nil {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Piperly.Colors.accent)
                .background(Circle().fill(Piperly.Colors.surface))
        }
    }
}
