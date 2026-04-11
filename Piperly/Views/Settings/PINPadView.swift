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

struct PINPadView: View {
    let title: String
    let subtitle: String?
    var onComplete: (String) -> Void

    @State private var entered = ""
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(Piperly.Typography.body)
                        .foregroundStyle(Piperly.Colors.textSecondary)
                }
            }

            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < entered.count
                              ? Piperly.Colors.accent
                              : Piperly.Colors.border)
                        .frame(width: 16, height: 16)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(80), spacing: 20), count: 3), spacing: 16) {
                ForEach(1...9, id: \.self) { digit in
                    digitButton("\(digit)")
                }

                Color.clear.frame(width: 80, height: 80)

                digitButton("0")

                Button {
                    if !entered.isEmpty {
                        entered.removeLast()
                    }
                } label: {
                    Image(systemName: "delete.backward")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Piperly.Colors.textSecondary)
                        .frame(width: 80, height: 80)
                        .contentShape(Rectangle())
                }
            }

            Spacer()
        }
        .padding(.horizontal, 40)
        .background(Piperly.Colors.background.ignoresSafeArea())
    }

    private func digitButton(_ digit: String) -> some View {
        Button {
            guard entered.count < 4 else { return }
            entered.append(digit)
            if entered.count == 4 {
                onComplete(entered)
            }
        } label: {
            Text(digit)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(Piperly.Colors.textPrimary)
                .frame(width: 80, height: 80)
                .background(Piperly.Colors.surfaceElevated)
                .clipShape(Circle())
        }
    }
}
