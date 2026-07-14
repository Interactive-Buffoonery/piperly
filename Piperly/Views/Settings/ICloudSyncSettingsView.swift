// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery

import SwiftUI

struct ICloudSyncSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var bookStore: BookStore
    @EnvironmentObject private var controller: ICloudSyncController
    @State private var isUnlocked = false
    @State private var confirmDisable = false
    @State private var confirmDiscard = false

    var body: some View {
        Group {
            if isUnlocked {
                controls
            } else {
                ParentGateView(
                    title: "iCloud Sync",
                    message: "A parent manages where the family library is stored and when it syncs.",
                    successTitle: "Manage iCloud Sync",
                    onSuccess: { isUnlocked = true }
                )
            }
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, newPhase in
            if ParentGateAccessPolicy.shouldReset(when: newPhase) {
                isUnlocked = false
                confirmDisable = false
                confirmDiscard = false
            }
        }
        .confirmationDialog(
            "Turn Off iCloud Sync?",
            isPresented: $confirmDisable,
            titleVisibility: .visible
        ) {
            Button("Turn Off Sync", role: .destructive) {
                Task { await controller.disable() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Network syncing will stop. Books and reading information already on this iPad will stay here. Nothing is deleted from iCloud.")
        }
        .confirmationDialog(
            "Discard Pending Work From the Previous Account?",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Pending Work", role: .destructive) {
                Task { await controller.confirmEnable(policy: .discardPendingChanges) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Piperly will first fetch this account's library, then discard only work "
                    + "that was waiting to upload to the previous account. This does not "
                    + "delete data from either iCloud account."
            )
        }
    }

    private var controls: some View {
        List {
            statusSection
            accountChoiceSection
            recoverySection
            privacySection
        }
        .scrollContentBackground(.hidden)
        .background(Piperly.Colors.background)
        .disabled(controller.isWorking)
    }

    private var statusSection: some View {
        let presentation = ICloudStatusPresentation(controller.status)
        return Section("Status") {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(presentation.explanation)
                        .font(Piperly.Typography.caption)
                        .foregroundStyle(Piperly.Colors.textSecondary)
                }
            } icon: {
                Image(systemName: presentation.symbolName)
                    .foregroundStyle(Piperly.Colors.accent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("iCloud sync status")
            .accessibilityValue("\(presentation.title). \(presentation.explanation)")

            if actions.showsEnable {
                Button("Enable iCloud Sync") {
                    Task { await controller.prepareEnable() }
                }
                .accessibilityHint("Checks the iCloud account before any information is uploaded")
            } else if actions.showsDisable {
                Button("Turn Off iCloud Sync", role: .destructive) {
                    confirmDisable = true
                }
                .accessibilityHint("Stops network sync and keeps local data")
            }

            if controller.isWorking {
                HStack {
                    ProgressView()
                    Text("Checking iCloud…")
                }
                .accessibilityElement(children: .combine)
            }

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(Piperly.Typography.caption)
                    .foregroundStyle(Piperly.Colors.error)
                    .accessibilityLabel("iCloud sync error. \(errorMessage)")
            }
        }
        .listRowBackground(Piperly.Colors.surface)
    }

    @ViewBuilder
    private var accountChoiceSection: some View {
        if let context = controller.confirmationContext {
            Section("Confirm iCloud Account") {
                Text(accountExplanation(context))
                    .font(Piperly.Typography.caption)
                    .foregroundStyle(Piperly.Colors.textSecondary)

                Button("Fetch iCloud, Then Keep and Upload Local Work") {
                    Task { await controller.confirmEnable(policy: .keepLocalAndUploadAfterFetch) }
                }
                .accessibilityHint("Fetches this account first, merges it with this iPad, then uploads local work")

                if actions.showsDiscardPendingWork {
                    Button("Discard Previous Account's Pending Work", role: .destructive) {
                        confirmDiscard = true
                    }
                    .accessibilityHint("Requires confirmation and never deletes either iCloud library")
                }
            }
            .listRowBackground(Piperly.Colors.surface)
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        if shouldOfferGeneralRetry || (actions.showsAssetRecovery && !retryableBooks.isEmpty) {
            Section("Recovery") {
                if shouldOfferGeneralRetry {
                    Button("Try Sync Again") {
                        Task { await controller.retrySync() }
                    }
                    .accessibilityHint("Retries iCloud without removing local data")
                }

                ForEach(actions.showsAssetRecovery ? retryableBooks : []) { book in
                    Button("Download \(book.title) Again") {
                        Task { await controller.retryBookAssets(contentIdentity: book.contentIdentity) }
                    }
                    .accessibilityLabel("Retry download for \(book.title)")
                    .accessibilityHint("Downloads this book from the private iCloud library")
                }
            }
            .listRowBackground(Piperly.Colors.surface)
        }
    }

    private var privacySection: some View {
        Section("What Uses iCloud") {
            Text(
                "EPUB files, book titles, reader profiles, reading state, bookmarks, saved "
                    + "words, and reader preferences sync through your private iCloud account "
                    + "and count against its storage quota."
            )
                .font(Piperly.Typography.caption)
                .foregroundStyle(Piperly.Colors.textSecondary)
            Text(
                "Piperly does not create a separate account. Turning sync off keeps local "
                    + "data. Deleting cloud data is a separate action and is not available "
                    + "on this screen."
            )
                .font(Piperly.Typography.caption)
                .foregroundStyle(Piperly.Colors.textSecondary)
        }
        .listRowBackground(Piperly.Colors.surface)
    }

    private var retryableBooks: [Book] {
        bookStore.books.filter { book in
            controller.failedAssetIdentities.contains(book.contentIdentity)
                || bookStore.assetAvailability(for: book) == .remoteOnly
                || bookStore.assetAvailability(for: book) == .retryableFailure
        }
    }

    private var shouldOfferGeneralRetry: Bool {
        actions.showsRetry
    }

    private var actions: ICloudSettingsActions {
        ICloudSettingsActions(
            status: controller.status,
            context: controller.confirmationContext,
            isEnabled: controller.isEnabled
        )
    }

    private func accountExplanation(_ context: SyncAccountConfirmationContext) -> String {
        switch context {
        case .firstEnable:
            return "Piperly will fetch this iCloud account before uploading this iPad's library."
        case .accountChanged:
            return "The iCloud account changed. Piperly will fetch the new account before syncing anything."
        case .accountChangedWithPendingWork:
            return "The iCloud account changed while work was waiting to upload. Choose "
                + "whether to keep that local work or discard it after Piperly fetches the new account."
        }
    }
}

struct ICloudSettingsActions: Equatable {
    let showsEnable: Bool
    let showsDisable: Bool
    let showsRetry: Bool
    let showsDiscardPendingWork: Bool
    let showsAssetRecovery: Bool

    init(
        status: LibrarySyncStatus,
        context: SyncAccountConfirmationContext?,
        isEnabled: Bool
    ) {
        showsEnable = !isEnabled && context == nil
        showsDisable = isEnabled
        showsDiscardPendingWork = context == .accountChangedWithPendingWork
        showsAssetRecovery = isEnabled && context == nil
        switch status {
        case .waitingToRetry, .blocked:
            showsRetry = isEnabled
        case .disabled, .idle, .syncing, .accountConfirmationRequired:
            showsRetry = false
        }
    }
}

enum ParentGateAccessPolicy {
    static func shouldReset(when scenePhase: ScenePhase) -> Bool {
        scenePhase != .active
    }
}

struct ICloudStatusPresentation: Equatable {
    let title: String
    let explanation: String
    let symbolName: String

    init(_ status: LibrarySyncStatus) {
        switch status {
        case .disabled:
            (title, explanation, symbolName) = (
                "Off",
                "Sync is disabled. Local books and reading information stay on this iPad.",
                "icloud.slash"
            )
        case .idle:
            (title, explanation, symbolName) = ("Up to Date", "Piperly is ready to sync changes through iCloud.", "checkmark.icloud")
        case .syncing:
            (title, explanation, symbolName) = (
                "Syncing",
                "Piperly is sending or receiving changes.",
                "arrow.triangle.2.circlepath.icloud"
            )
        case .waitingToRetry(let date):
            let time = date.map { " after \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            (title, explanation, symbolName) = (
                "Waiting to Retry",
                "iCloud is temporarily unavailable. Piperly will retry\(time).",
                "clock.badge.exclamationmark"
            )
        case .accountConfirmationRequired:
            (title, explanation, symbolName) = (
                "Account Confirmation Needed",
                "A parent must confirm the current iCloud account before syncing resumes.",
                "person.crop.circle.badge.questionmark"
            )
        case .blocked(let failure):
            (title, explanation, symbolName) = ("Needs Attention", Self.explanation(for: failure), "exclamationmark.icloud")
        }
    }

    private static func explanation(for failure: SyncFailure) -> String {
        switch failure {
        case .retryable:
            return "iCloud is temporarily unavailable. Try again."
        case .accountUnavailable:
            return "Sign in to iCloud in iPad Settings, then try again."
        case .accountRestricted:
            return "iCloud access is restricted on this iPad."
        case .quotaExceeded:
            return "The iCloud storage quota is full. Free space, then try again."
        case .permissionDenied:
            return "iCloud did not allow this sync. Check account settings, then try again."
        case .invalidSchema:
            return "This build cannot use the current iCloud database. Contact support before retrying."
        case .missingLocalData:
            return "A book file is missing or damaged. Retry that book below."
        case .unknown:
            return "Sync stopped safely. Your local data is unchanged. Try again."
        }
    }
}
