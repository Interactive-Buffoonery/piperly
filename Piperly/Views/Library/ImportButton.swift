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
