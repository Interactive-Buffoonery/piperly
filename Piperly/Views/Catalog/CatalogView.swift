import SwiftUI

struct CatalogView: View {
    @EnvironmentObject var opdsService: OPDSService
    @EnvironmentObject var bookStore: BookStore
    var onOpenBook: ((Book) -> Void)?
    @State private var searchText = ""
    @State private var selectedItem: CatalogItem?

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 24)
    ]

    var body: some View {
        ZStack {
            Piperly.Colors.background.ignoresSafeArea()

            if !opdsService.isConfigured {
                notConfiguredState
            } else if opdsService.isLoading && opdsService.catalogItems.isEmpty {
                ProgressView()
                    .tint(Piperly.Colors.accent)
            } else if let error = opdsService.error, opdsService.catalogItems.isEmpty {
                errorState(error)
            } else {
                catalogContent
            }
        }
        .task {
            if opdsService.catalogItems.isEmpty && opdsService.error == nil {
                await opdsService.loadCatalog()
            }
        }
        .sheet(item: $selectedItem) { item in
            CatalogDetailSheet(
                item: item,
                isAlreadyDownloaded: isDownloaded(item),
                onDownload: { downloadItem(item) },
                onOpenBook: {
                    if let book = bookStore.books.first(where: {
                        $0.title.localizedCaseInsensitiveCompare(item.title) == .orderedSame
                    }) {
                        selectedItem = nil
                        onOpenBook?(book)
                    }
                }
            )
            .environmentObject(opdsService)
            .environmentObject(bookStore)
        }
    }

    private var catalogContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if opdsService.canGoBack {
                    Button {
                        Task { await opdsService.navigateBack() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(Piperly.Typography.body)
                        .foregroundStyle(Piperly.Colors.accent)
                    }
                    .padding(.horizontal, 24)
                }

                if !opdsService.feedTitle.isEmpty {
                    Text(opdsService.feedTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Piperly.Colors.textPrimary)
                        .padding(.horizontal, 24)
                }

                if !opdsService.navigationLinks.isEmpty {
                    navigationSection
                }

                if !opdsService.catalogItems.isEmpty {
                    booksGrid
                }

                if opdsService.hasNextPage {
                    Button {
                        Task { await opdsService.loadNextPage() }
                    } label: {
                        HStack {
                            if opdsService.isLoading {
                                ProgressView()
                                    .tint(Piperly.Colors.accent)
                            }
                            Text("Load More")
                                .font(Piperly.Typography.body)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Piperly.Colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Piperly.Colors.accent)
                    }
                    .padding(.horizontal, 24)
                    .disabled(opdsService.isLoading)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(opdsService.navigationLinks) { link in
                Button {
                    Task { await opdsService.navigate(to: link.href, title: link.title) }
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Piperly.Colors.accent)
                        Text(link.title)
                            .font(Piperly.Typography.body)
                            .foregroundStyle(Piperly.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Piperly.Colors.textTertiary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
            }
        }
        .background(Piperly.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    private var booksGrid: some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(opdsService.catalogItems) { item in
                CatalogBookCard(
                    item: item,
                    downloadProgress: opdsService.activeDownloads[item.id],
                    isAlreadyDownloaded: isDownloaded(item)
                )
                .onTapGesture { selectedItem = item }
            }
        }
        .padding(.horizontal, 24)
    }

    private var notConfiguredState: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.wifi")
                .font(.system(size: 64))
                .foregroundStyle(Piperly.Colors.textTertiary)
            Text("No book server")
                .font(Piperly.Typography.title)
                .foregroundStyle(Piperly.Colors.textPrimary)
            Text("Ask a grown-up to set up a server in Settings")
                .font(Piperly.Typography.body)
                .foregroundStyle(Piperly.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func errorState(_ error: OPDSError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(Piperly.Colors.textTertiary)
            Text(error.friendlyMessage)
                .font(Piperly.Typography.body)
                .foregroundStyle(Piperly.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await opdsService.loadCatalog() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(Piperly.Typography.body)
                    .foregroundStyle(Piperly.Colors.accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Piperly.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }

    private func isDownloaded(_ item: CatalogItem) -> Bool {
        bookStore.books.contains {
            $0.title.localizedCaseInsensitiveCompare(item.title) == .orderedSame
        }
    }

    private func downloadItem(_ item: CatalogItem) {
        Task {
            do {
                try await opdsService.downloadBook(item, to: bookStore)
            } catch let error as OPDSError {
                opdsService.error = error
            } catch {
                opdsService.error = .downloadFailed(error.localizedDescription)
            }
        }
    }
}
