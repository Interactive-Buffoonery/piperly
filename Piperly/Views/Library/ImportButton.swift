import SwiftUI
import UniformTypeIdentifiers

struct ImportButton: View {
    let onImport: (URL) -> Void
    @State private var showingImporter = false

    var body: some View {
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
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            onImport(url)
        }
    }
}
