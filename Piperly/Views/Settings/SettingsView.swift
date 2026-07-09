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
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bookStore: BookStore
    @EnvironmentObject private var iCloudSyncController: ICloudSyncController

    @State private var isVoiceListExpanded = false
    @State private var voices: [Voice] = []

    let ttsEngine: TTSEngine

    private var theme: ReaderTheme {
        bookStore.activeReaderTheme
    }

    private var selectedVoiceName: String {
        if let voice = voices.first(where: { $0.id == bookStore.activeVoiceIdentifier }) {
            return voice.name
        }
        return voices.first?.name ?? "Choose Voice"
    }

    var body: some View {
        NavigationStack {
            List {
                profilesSection
                iCloudSection
                readingSection
                voicesSection
            }
            .scrollContentBackground(.hidden)
            .background(Piperly.Colors.background)
            .navigationTitle("Settings")
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
        .onAppear {
            refreshVoices()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVSpeechSynthesizer.availableVoicesDidChangeNotification
            )
        ) { _ in
            refreshVoices()
        }
        .presentationDetents([.large])
        .presentationBackground(Piperly.Colors.background)
    }

    private var iCloudSection: some View {
        Section {
            NavigationLink {
                ICloudSyncSettingsView()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Piperly.Colors.accent)
                        .frame(width: 30)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("iCloud Sync")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Piperly.Colors.textPrimary)
                        Text(ICloudStatusPresentation(iCloudSyncController.status).title)
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textTertiary)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityLabel("iCloud Sync")
            .accessibilityValue(ICloudStatusPresentation(iCloudSyncController.status).title)
            .accessibilityHint("Opens parent controls for private iCloud sync")
        } header: {
            Text("Parent Controls")
                .foregroundStyle(Piperly.Colors.textSecondary)
        }
        .listRowBackground(Piperly.Colors.surface)
    }

    private var profilesSection: some View {
        Section {
            NavigationLink {
                ReaderProfilesView()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Piperly.Colors.accent)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reader Profiles")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Piperly.Colors.textPrimary)
                        Text("\(bookStore.profiles.count) profile\(bookStore.profiles.count == 1 ? "" : "s")")
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textTertiary)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityLabel("Reader Profiles")
            .accessibilityHint("Manage child reader profiles")
        } header: {
            Text("Family")
                .foregroundStyle(Piperly.Colors.textSecondary)
        }
        .listRowBackground(Piperly.Colors.surface)
    }

    private var readingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Font Size")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                HStack {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                    Slider(value: bookStore.activeFontSizeBinding, in: 18...30, step: 1) {
                        Text("Font Size")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .labelsHidden()
                    .tint(Piperly.Colors.accent)
                    Image(systemName: "textformat.size.larger")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 12) {
                Text("Reader Theme")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(ReaderTheme.allCases) { readerTheme in
                            Button {
                                withAnimation(.snappy) {
                                    bookStore.activeReaderThemeBinding.wrappedValue = readerTheme.rawValue
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: readerTheme.backgroundColor))
                                        .frame(width: 52, height: 52)
                                        .overlay {
                                            Text("Aa")
                                                .font(readerTheme.fontFamily == .serif
                                                    ? .system(size: 16, weight: .medium, design: .serif)
                                                    : .system(size: 16, weight: .medium, design: .default))
                                                .foregroundStyle(Color(hex: readerTheme.textColor))
                                        }
                                        .overlay {
                                            Circle()
                                                .stroke(Piperly.Colors.accent, lineWidth: 3)
                                                .opacity(theme == readerTheme ? 1 : 0)
                                        }
                                    Text(readerTheme.displayName)
                                        .font(.system(
                                            size: 11,
                                            weight: theme == readerTheme ? .semibold : .regular,
                                            design: .rounded
                                        ))
                                        .foregroundStyle(theme == readerTheme ? Piperly.Colors.accent : Piperly.Colors.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(readerTheme.displayName)
                            .accessibilityAddTraits(theme == readerTheme ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }

                ReaderThemePreview(theme: theme, fontSize: bookStore.activeFontSize)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Reading")
                .foregroundStyle(Piperly.Colors.textSecondary)
        }
        .listRowBackground(Piperly.Colors.surface)
    }

    private var voicesSection: some View {
        Section {
            Button {
                withAnimation(.snappy) {
                    isVoiceListExpanded.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Piperly.Colors.accent)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Voice")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Piperly.Colors.textPrimary)
                        Text(selectedVoiceName)
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Piperly.Colors.textTertiary)
                        .rotationEffect(.degrees(isVoiceListExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice")
            .accessibilityValue(selectedVoiceName)
            .accessibilityHint(isVoiceListExpanded ? "Collapse voice list" : "Expand voice list")

            if isVoiceListExpanded {
                VStack(spacing: 10) {
                    if voices.isEmpty {
                        unavailableVoicesMessage
                    } else {
                        ForEach(voices) { voice in
                            SettingsVoiceRow(
                                voice: voice,
                                isSelected: voice.id == bookStore.activeVoiceIdentifier,
                                onSelect: { bookStore.activeVoiceIdentifierBinding.wrappedValue = voice.id },
                                onPreview: {
                                    ttsEngine.speak(
                                        word: "Hi, I'm \(voice.name)!",
                                        voiceIdentifier: voice.id,
                                        rate: Float(bookStore.activeSpeechRate)
                                    )
                                }
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Voice Speed")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                HStack {
                    Image(systemName: "tortoise")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                    Slider(value: bookStore.activeSpeechRateBinding, in: 0.30...0.60, step: 0.05) {
                        Text("Voice Speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                    .labelsHidden()
                    .tint(Piperly.Colors.accent)
                    Image(systemName: "hare")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Voices")
                .foregroundStyle(Piperly.Colors.textSecondary)
        }
        .listRowBackground(Piperly.Colors.surface)
    }

    private var unavailableVoicesMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 24))
                .foregroundStyle(Piperly.Colors.textTertiary)
            Text("No voices available")
                .font(Piperly.Typography.body)
                .foregroundStyle(Piperly.Colors.textSecondary)
            Text("Download Premium or Enhanced voices in the iOS Settings app under Accessibility > Read & Speak or Spoken Content > Voices.")
                .font(Piperly.Typography.caption)
                .foregroundStyle(Piperly.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func refreshVoices() {
        voices = Voice.availableVoices()
        if !voices.contains(where: { $0.id == bookStore.activeVoiceIdentifier }),
           let first = voices.first {
            bookStore.activeVoiceIdentifierBinding.wrappedValue = first.id
        }
    }
}

private struct ReaderThemePreview: View {
    let theme: ReaderTheme
    let fontSize: Double

    private var sampleFont: Font {
        theme.fontFamily == .serif
            ? .system(size: fontSize, weight: .regular, design: .serif)
            : .system(size: fontSize, weight: .regular, design: .default)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The little door opened into a garden full of warm light.")
                .font(sampleFont)
                .lineSpacing(6)
                .foregroundStyle(Color(hex: theme.textColor))

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: theme.textColor).opacity(0.28))
                    .frame(width: 76, height: 7)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: theme.textColor).opacity(0.18))
                    .frame(width: 118, height: 7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: theme.backgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: theme.textColor).opacity(theme.isDark ? 0.18 : 0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Theme preview")
    }
}

private struct SettingsVoiceRow: View {
    let voice: Voice
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPreview) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Piperly.Colors.background)
                    .frame(width: 34, height: 34)
                    .background(Piperly.Colors.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(voice.name)")

            Button(action: onSelect) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name)
                            .font(Piperly.Typography.body)
                            .foregroundStyle(Piperly.Colors.textPrimary)
                        Text("\(voice.language) \u{2022} \(voice.quality.rawValue)")
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textTertiary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Piperly.Colors.accent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isSelected ? Piperly.Colors.surfaceElevated : Piperly.Colors.background.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.name)
            .accessibilityValue(isSelected ? "Selected" : voice.quality.rawValue)
        }
    }
}

private struct ReaderProfilesView: View {
    @EnvironmentObject private var bookStore: BookStore
    @State private var isUnlocked = false
    @State private var showingAddProfile = false
    @State private var editingProfile: ReaderProfile?
    @State private var profilePendingDeletion: ReaderProfile?

    var body: some View {
        Group {
            if isUnlocked {
                profileManagementList
            } else {
                ParentGateView(
                    title: "Reader Profiles",
                    message: "Profiles use nicknames, avatar symbols, and colors only.",
                    successTitle: "Continue",
                    onSuccess: { isUnlocked = true }
                )
            }
        }
        .navigationTitle("Reader Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isUnlocked {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Profile", systemImage: "plus") {
                        showingAddProfile = true
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Piperly.Colors.accent)
                    .accessibilityLabel("Add Profile")
                }
            }
        }
        .sheet(isPresented: $showingAddProfile) {
            ProfileEditorView(
                title: "Add Profile",
                profile: nil,
                onSave: { draft in
                    try bookStore.addProfile(
                        name: draft.name,
                        avatarSymbol: draft.avatarSymbol,
                        colorName: draft.colorName
                    )
                }
            )
            .presentationDetents([.large])
            .presentationBackground(Piperly.Colors.background)
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorView(
                title: "Edit Profile",
                profile: profile,
                onSave: { draft in
                    try bookStore.updateProfile(
                        profile.id,
                        name: draft.name,
                        avatarSymbol: draft.avatarSymbol,
                        colorName: draft.colorName
                    )
                }
            )
            .presentationDetents([.large])
            .presentationBackground(Piperly.Colors.background)
        }
        .sheet(item: $profilePendingDeletion) { profile in
            DeleteProfileGateView(profile: profile) {
                bookStore.deleteProfile(profile.id)
            }
            .presentationDetents([.medium])
            .presentationBackground(Piperly.Colors.background)
        }
    }

    private var profileManagementList: some View {
        List {
            Section {
                ForEach(bookStore.profiles) { profile in
                    ReaderProfileRow(
                        profile: profile,
                        isSelected: profile.id == bookStore.activeProfile.id,
                        canDelete: bookStore.profiles.count > 1,
                        onSelect: { bookStore.selectProfile(profile.id) },
                        onEdit: { editingProfile = profile },
                        onDelete: { profilePendingDeletion = profile }
                    )
                }
            } footer: {
                Text("Privacy guardrails: use nicknames only. Piperly does not ask for birthdays, photos, full names, email addresses, or Apple IDs.")
                    .foregroundStyle(Piperly.Colors.textTertiary)
            }
            .listRowBackground(Piperly.Colors.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Piperly.Colors.background)
    }
}

private struct ReaderProfileRow: View {
    let profile: ReaderProfile
    let isSelected: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarBadge(symbol: profile.avatarSymbol, colorName: profile.colorName, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textPrimary)
                Text(isSelected ? "Current reader" : "Available reader")
                    .font(Piperly.Typography.caption)
                    .foregroundStyle(Piperly.Colors.textTertiary)
            }

            Spacer()

            Button(isSelected ? "Selected" : "Switch", action: onSelect)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .buttonStyle(.bordered)
                .tint(isSelected ? Piperly.Colors.success : Piperly.Colors.accent)
                .disabled(isSelected)
                .accessibilityLabel(isSelected ? "\(profile.name) selected" : "Switch to \(profile.name)")

            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    .disabled(!canDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(Piperly.Colors.accent)
            .accessibilityLabel("More options for \(profile.name)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

private struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProfileDraft

    let title: String
    let onSave: (ProfileDraft) throws -> Void

    init(title: String, profile: ReaderProfile?, onSave: @escaping (ProfileDraft) throws -> Void) {
        self.title = title
        self.onSave = onSave
        _draft = State(initialValue: ProfileDraft(profile: profile))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Nickname", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Nickname")
                } footer: {
                    Text(nameMessage)
                        .foregroundStyle(nameError == nil ? Piperly.Colors.textTertiary : Piperly.Colors.error)
                }
                .listRowBackground(Piperly.Colors.surface)

                Section("Avatar") {
                    AvatarGridView(
                        selectedSymbol: $draft.avatarSymbol,
                        colorName: draft.colorName
                    )
                }
                .listRowBackground(Piperly.Colors.surface)

                Section {
                    ProfileColorPickerView(selectedColorName: $draft.colorName)
                } header: {
                    Text("Color")
                } footer: {
                    Text("Profiles never use photos or account identifiers.")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                }
                .listRowBackground(Piperly.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Piperly.Colors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Piperly.Colors.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if (try? onSave(draft)) != nil {
                            dismiss()
                        }
                    }
                    .disabled(nameError != nil)
                    .foregroundStyle(Piperly.Colors.accent)
                }
            }
            .toolbarBackground(Piperly.Colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var nameMessage: String {
        nameError ?? "Use a nickname only. Do not enter full names, birthdays, email addresses, or Apple IDs."
    }

    private var nameError: String? {
        ProfileDraft.validationError(for: draft.name)
    }
}

private struct AvatarGridView: View {
    @Binding var selectedSymbol: String
    let colorName: String

    private let columns = [GridItem(.adaptive(minimum: 58), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ProfileDraft.avatarSymbols, id: \.self) { symbol in
                let isSelected = selectedSymbol == symbol

                Button {
                    selectedSymbol = symbol
                } label: {
                    AvatarChoiceIcon(
                        symbol: symbol,
                        colorName: colorName,
                        isSelected: isSelected
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Avatar \(symbol)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AvatarChoiceIcon: View {
    let symbol: String
    let colorName: String
    let isSelected: Bool

    var body: some View {
        let tint = profileColor(colorName)

        Image(systemName: symbol)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(isSelected ? AnyShapeStyle(Piperly.Colors.background) : AnyShapeStyle(tint))
            .frame(width: 54, height: 54)
            .background(isSelected ? tint : Piperly.Colors.surfaceElevated)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Piperly.Colors.accent, lineWidth: isSelected ? 2 : 0)
            }
    }
}

private struct ProfileColorPickerView: View {
    @Binding var selectedColorName: String

    var body: some View {
        HStack(spacing: 14) {
            ForEach(ProfileDraft.colorNames, id: \.self) { colorName in
                let isSelected = selectedColorName == colorName

                Button {
                    selectedColorName = colorName
                } label: {
                    ColorChoiceCircle(colorName: colorName, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(colorName.capitalized) color")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ColorChoiceCircle: View {
    let colorName: String
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(profileColor(colorName))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Piperly.Colors.background)
                    .opacity(isSelected ? 1 : 0)
            }
            .overlay {
                Circle()
                    .stroke(Piperly.Colors.textPrimary.opacity(0.35), lineWidth: 1)
            }
    }
}

private struct DeleteProfileGateView: View {
    @Environment(\.dismiss) private var dismiss
    let profile: ReaderProfile
    let onDelete: () -> Void

    var body: some View {
        ParentGateView(
            title: "Delete \(profile.name)?",
            message: "This removes this profile's words, bookmarks, progress, and profile settings. Shared books stay in the library.",
            successTitle: "Delete Profile",
            successRole: .destructive,
            onSuccess: {
                onDelete()
                dismiss()
            }
        )
    }
}

struct ParentGateView: View {
    let title: String
    let message: String
    let successTitle: String
    var successRole: ButtonRole?
    let onSuccess: () -> Void

    @State private var left = Int.random(in: 4...9)
    @State private var right = Int.random(in: 2...8)
    @State private var answer = ""
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 42))
                .foregroundStyle(Piperly.Colors.accent)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textPrimary)
                Text(message)
                    .font(Piperly.Typography.body)
                    .foregroundStyle(Piperly.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Parent check: what is \(left) + \(right)?")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)

                TextField("Answer", text: $answer)
                    .keyboardType(.numberPad)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .padding(14)
                    .background(Piperly.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Piperly.Colors.textPrimary)
                    .accessibilityLabel("Parent check answer")

                if let errorText {
                    Text(errorText)
                        .font(Piperly.Typography.caption)
                        .foregroundStyle(Piperly.Colors.error)
                }
            }
            .frame(maxWidth: 320)

            Button(role: successRole) {
                submit()
            } label: {
                Text(successTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 320)
                    .padding(.vertical, 12)
                    .background(Piperly.Colors.accent)
                    .foregroundStyle(Piperly.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Piperly.Colors.background)
    }

    private func submit() {
        guard Int(answer) == left + right else {
            errorText = "Try again."
            answer = ""
            left = Int.random(in: 4...9)
            right = Int.random(in: 2...8)
            return
        }
        onSuccess()
    }
}

private struct ProfileAvatarBadge: View {
    let symbol: String
    let colorName: String
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(Piperly.Colors.background)
            .frame(width: size, height: size)
            .background(profileColor(colorName))
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

private struct ProfileDraft {
    static let avatarSymbols = [
        "person.crop.circle.fill",
        "sparkles",
        "star.fill",
        "moon.stars.fill",
        "sun.max.fill",
        "leaf.fill",
        "book.fill",
        "heart.fill"
    ]
    static let colorNames = ["accent", "green", "tan", "warning", "info", "error"]

    var name: String
    var avatarSymbol: String
    var colorName: String

    init(profile: ReaderProfile?) {
        name = profile?.name ?? ""
        avatarSymbol = profile?.avatarSymbol ?? ReaderProfile.defaultAvatarSymbol
        colorName = profile?.colorName ?? ReaderProfile.defaultColorName
    }

    static func validationError(for name: String) -> String? {
        ReaderProfile.nicknameValidationError(for: name)?.localizedDescription
    }
}

private func profileColor(_ name: String) -> Color {
    switch name {
    case "teal", "accent":
        return Piperly.Colors.teal
    case "green":
        return Piperly.Colors.green
    case "tan":
        return Piperly.Colors.tan
    case "warning":
        return Piperly.Colors.warning
    case "info":
        return Piperly.Colors.info
    case "error":
        return Piperly.Colors.error
    default:
        return Piperly.Colors.accent
    }
}
