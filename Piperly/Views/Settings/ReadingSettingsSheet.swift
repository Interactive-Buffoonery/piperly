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

struct ReadingSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bookStore: BookStore

    private var theme: ReaderTheme {
        bookStore.activeReaderTheme
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Piperly.Colors.background.ignoresSafeArea()

                VStack(spacing: 32) {
                    // Reader theme
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reader Theme")
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(ReaderTheme.allCases) { t in
                                    Button {
                                        bookStore.activeReaderThemeBinding.wrappedValue = t.rawValue
                                    } label: {
                                        VStack(spacing: 8) {
                                            Circle()
                                                .fill(Color(hex: t.backgroundColor))
                                                .frame(width: 64, height: 64)
                                                .overlay {
                                                    Text("Aa")
                                                        .font(t.fontFamily == .serif
                                                            ? .system(size: 20, weight: .medium, design: .serif)
                                                            : .system(size: 20, weight: .medium, design: .default))
                                                        .foregroundStyle(Color(hex: t.textColor))
                                                }
                                                .overlay {
                                                    Circle()
                                                        .stroke(Piperly.Colors.accent, lineWidth: 3)
                                                        .opacity(theme == t ? 1 : 0)
                                                }
                                                .shadow(color: t.isDark ? .clear : .black.opacity(0.15), radius: 4, y: 2)
                                            Text(t.displayName)
                                                .font(.system(size: 12, weight: theme == t ? .semibold : .regular))
                                                .foregroundStyle(theme == t ? Piperly.Colors.accent : Piperly.Colors.textSecondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }
                    }

                    // Font size
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Font Size")
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                        HStack {
                            Text("A")
                                .font(.system(size: 14))
                                .foregroundStyle(Piperly.Colors.textTertiary)
                            Slider(value: bookStore.activeFontSizeBinding, in: 18...30, step: 1)
                                .tint(Piperly.Colors.accent)
                            Text("A")
                                .font(.system(size: 24))
                                .foregroundStyle(Piperly.Colors.textPrimary)
                        }
                    }

                    // TTS Speed
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Voice Speed")
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                        HStack {
                            Image(systemName: "tortoise")
                                .foregroundStyle(Piperly.Colors.textTertiary)
                            Slider(value: bookStore.activeSpeechRateBinding, in: 0.30...0.60, step: 0.05)
                                .tint(Piperly.Colors.accent)
                            Image(systemName: "hare")
                                .foregroundStyle(Piperly.Colors.textPrimary)
                        }
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Piperly.Colors.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Piperly.Colors.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
