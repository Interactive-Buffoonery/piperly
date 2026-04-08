import SwiftUI

struct PINPadView: View {
    let title: String
    let subtitle: String?
    var onComplete: (String) -> Void

    @State private var entered = ""
    @State private var shakeOffset: CGFloat = 0

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
            .offset(x: shakeOffset)

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

    func shake() {
        entered = ""
        withAnimation(.easeInOut(duration: 0.08).repeatCount(5, autoreverses: true)) {
            shakeOffset = 12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            shakeOffset = 0
        }
    }
}
