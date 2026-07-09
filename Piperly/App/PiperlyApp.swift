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

@main
struct PiperlyApp: App {
    @StateObject private var bookStore: BookStore
    @StateObject private var iCloudSyncController: ICloudSyncController
    private let ttsEngine = TTSEngine()
    @State private var showVoiceSetup = false
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init() {
        let router = LibrarySyncRouter()
        let store = BookStore(librarySync: router)
        _bookStore = StateObject(wrappedValue: store)

        _iCloudSyncController = StateObject(wrappedValue: ICloudSyncController(
            router: router,
            localSnapshotProvider: { [weak store] in
                store?.librarySnapshotRecords() ?? []
            },
            localBookAssetProvider: { [weak store] book in
                store?.localBookAssets(for: book)
            },
            assetStagingURL: store.assetStagingURL,
            remoteChangeHandler: { [weak store] changes, scope in
                guard let store else { return .complete }
                if scope.isCurrentAccount {
                    return router.applyingCurrentAccountChanges(scope: scope) {
                        store.applyRemoteChanges(changes)
                    }
                }
                return store.applyRemoteChanges(changes)
            }
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(ttsEngine: ttsEngine)
                .environmentObject(bookStore)
                .environmentObject(iCloudSyncController)
                .task {
                    await iCloudSyncController.startIfEnabled()
                    await bookStore.importSampleBooksIfNeeded()
                }
                .onChange(of: bookStore.selectedProfileID, initial: true) {
                    if !bookStore.activeProfile.hasCompletedVoiceSetup {
                        showVoiceSetup = true
                    }
                }
                .sheet(isPresented: $showVoiceSetup) {
                    VoiceSetupSheet(ttsEngine: ttsEngine)
                        .environmentObject(bookStore)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        bookStore.flushPendingSaves()
                    }
                }
        }
    }
}
