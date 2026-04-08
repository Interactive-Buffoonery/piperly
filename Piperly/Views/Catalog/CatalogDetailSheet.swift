import SwiftUI

struct CatalogDetailSheet: View {
    let item: CatalogItem
    let isAlreadyDownloaded: Bool
    let onDownload: () -> Void

    @EnvironmentObject var opdsService: OPDSService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var imageLoader = AuthenticatedImageLoader()

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

                    // Download button
                    if isAlreadyDownloaded {
                        Label("In Your Library", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Piperly.Colors.success)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(Piperly.Colors.success.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
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
        .presentationDetents([.medium, .large])
        .presentationBackground(Piperly.Colors.background)
        .task {
            if let coverURL = item.coverURL {
                await imageLoader.load(url: coverURL)
            }
        }
    }
}
