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

struct PINFlowView: View {
    enum Step {
        case verifyCurrent
        case setNew
        case confirmNew
    }

    let step: Step
    var pinManager: PINManager?
    let onCancel: () -> Void
    let onComplete: (String) -> Void

    @State private var currentStep: Step
    @State private var newPIN = ""
    @State private var flowKey = UUID()

    init(step: Step, pinManager: PINManager? = nil, onCancel: @escaping () -> Void, onComplete: @escaping (String) -> Void) {
        self.step = step
        self.pinManager = pinManager
        self.onCancel = onCancel
        self.onComplete = onComplete
        _currentStep = State(initialValue: step)
    }

    var body: some View {
        ZStack {
            Piperly.Colors.background.ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Piperly.Colors.textTertiary)
                    }
                    .padding()
                }
                Spacer()
            }

            switch currentStep {
            case .verifyCurrent:
                PINPadView(
                    title: "Enter Current PIN",
                    subtitle: nil
                ) { pin in
                    if pinManager?.verifyPIN(pin) == true {
                        currentStep = .setNew
                        flowKey = UUID()
                    } else {
                        flowKey = UUID()
                    }
                }
                .id(flowKey)

            case .setNew:
                PINPadView(
                    title: "Set a New PIN",
                    subtitle: "Choose a 4-digit code"
                ) { pin in
                    newPIN = pin
                    currentStep = .confirmNew
                    flowKey = UUID()
                }
                .id(flowKey)

            case .confirmNew:
                PINPadView(
                    title: "Confirm PIN",
                    subtitle: "Enter the same code again"
                ) { pin in
                    if pin == newPIN {
                        onComplete(pin)
                    } else {
                        currentStep = .setNew
                        newPIN = ""
                        flowKey = UUID()
                    }
                }
                .id(flowKey)
            }
        }
    }
}
