import SwiftUI

struct PINGateModifier<Destination: View>: ViewModifier {
    @EnvironmentObject var pinManager: PINManager
    @Binding var isPresented: Bool
    @ViewBuilder var destination: () -> Destination

    @State private var showPINPad = false
    @State private var showDestination = false
    @State private var pinPadKey = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, present in
                guard present else { return }
                isPresented = false
                if pinManager.isPINSet {
                    pinPadKey = UUID()
                    showPINPad = true
                } else {
                    showDestination = true
                }
            }
            .fullScreenCover(isPresented: $showPINPad) {
                ZStack {
                    Piperly.Colors.background.ignoresSafeArea()

                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                showPINPad = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Piperly.Colors.textTertiary)
                            }
                            .padding()
                        }
                        Spacer()
                    }

                    PINPadView(
                        title: "Enter PIN",
                        subtitle: "Ask a grown-up for the code"
                    ) { pin in
                        if pinManager.verifyPIN(pin) {
                            showPINPad = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showDestination = true
                            }
                        } else {
                            pinPadKey = UUID()
                        }
                    }
                    .id(pinPadKey)
                }
            }
            .sheet(isPresented: $showDestination) {
                destination()
                    .environmentObject(pinManager)
            }
    }
}

extension View {
    func pinGated<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        modifier(PINGateModifier(isPresented: isPresented, destination: destination))
    }
}
