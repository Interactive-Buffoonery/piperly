import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var pinManager: PINManager
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var showSetPIN = false
    @State private var showChangePIN = false
    @State private var showRemovePIN = false

    @AppStorage("readerFontSize") private var fontSize: Double = 22
    @AppStorage("readerTheme") private var selectedTheme: String = ReaderTheme.piperly.rawValue
    @AppStorage("speechRate") private var speechRate: Double = 0.45

    private var theme: ReaderTheme {
        ReaderTheme(rawValue: selectedTheme) ?? .piperly
    }

    enum ConnectionStatus: Equatable {
        case idle
        case testing
        case success
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            List {
                parentalPINSection
                bookServerSection
                readingSection
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
        .presentationDetents([.large])
        .presentationBackground(Piperly.Colors.background)
        .onAppear { loadServerConfig() }
        .fullScreenCover(isPresented: $showSetPIN) {
            setPINFlow()
        }
        .fullScreenCover(isPresented: $showChangePIN) {
            changePINFlow()
        }
        .fullScreenCover(isPresented: $showRemovePIN) {
            removePINFlow()
        }
    }

    // MARK: - Parental PIN Section

    private var parentalPINSection: some View {
        Section {
            if pinManager.isPINSet {
                Button("Change PIN") {
                    showChangePIN = true
                }
                .foregroundStyle(Piperly.Colors.accent)

                Button("Remove PIN") {
                    showRemovePIN = true
                }
                .foregroundStyle(Piperly.Colors.error)
            } else {
                Button("Set a PIN") {
                    showSetPIN = true
                }
                .foregroundStyle(Piperly.Colors.accent)
            }
        } header: {
            Text("Parental PIN")
                .foregroundStyle(Piperly.Colors.textSecondary)
        } footer: {
            Text(pinManager.isPINSet
                 ? "A PIN is required to access Settings and Browse."
                 : "Set a 4-digit PIN to restrict access to Settings and the book server.")
                .foregroundStyle(Piperly.Colors.textTertiary)
        }
        .listRowBackground(Piperly.Colors.surface)
    }

    // MARK: - Book Server Section

    private var bookServerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Server URL")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                TextField("http://192.168.1.100:13378/opds/v1.2/catalog", text: $serverURL, prompt: Text("Server URL").foregroundStyle(Piperly.Colors.textTertiary))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .foregroundStyle(Piperly.Colors.textPrimary)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Username")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                TextField("Username", text: $username, prompt: Text("Username").foregroundStyle(Piperly.Colors.textTertiary))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Piperly.Colors.textPrimary)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                SecureField("Password", text: $password, prompt: Text("Password").foregroundStyle(Piperly.Colors.textTertiary))
                    .foregroundStyle(Piperly.Colors.textPrimary)
            }
            .padding(.vertical, 4)

            Button {
                saveServerConfig()
                testConnection()
            } label: {
                HStack {
                    Text("Test Connection")
                    Spacer()
                    switch connectionStatus {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView()
                            .tint(Piperly.Colors.accent)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Piperly.Colors.success)
                    case .failed:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Piperly.Colors.error)
                    }
                }
            }
            .foregroundStyle(Piperly.Colors.accent)
            .disabled(serverURL.isEmpty || connectionStatus == .testing)

            if case .failed(let message) = connectionStatus {
                Text(message)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Piperly.Colors.error)
            }
        } header: {
            Text("Book Server")
                .foregroundStyle(Piperly.Colors.textSecondary)
        } footer: {
            Text("Connect to an OPDS-compatible book server like Audiobookshelf.")
                .foregroundStyle(Piperly.Colors.textTertiary)
        }
        .listRowBackground(Piperly.Colors.surface)
    }

    // MARK: - Reading Section

    private var readingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Font Size")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                HStack {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                    Slider(value: $fontSize, in: 18...30, step: 1)
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
                        ForEach(ReaderTheme.allCases) { t in
                            Button {
                                selectedTheme = t.rawValue
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: t.backgroundColor))
                                        .frame(width: 52, height: 52)
                                        .overlay {
                                            Text("Aa")
                                                .font(t.fontFamily == .serif
                                                    ? .system(size: 16, weight: .medium, design: .serif)
                                                    : .system(size: 16, weight: .medium, design: .default))
                                                .foregroundStyle(Color(hex: t.textColor))
                                        }
                                        .overlay {
                                            Circle()
                                                .stroke(Piperly.Colors.accent, lineWidth: 3)
                                                .opacity(theme == t ? 1 : 0)
                                        }
                                    Text(t.displayName)
                                        .font(.system(size: 11, weight: theme == t ? .semibold : .regular, design: .rounded))
                                        .foregroundStyle(theme == t ? Piperly.Colors.accent : Piperly.Colors.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Voice Speed")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                HStack {
                    Image(systemName: "tortoise")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                    Slider(value: $speechRate, in: 0.30...0.60, step: 0.05)
                        .tint(Piperly.Colors.accent)
                    Image(systemName: "hare")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Reading")
                .foregroundStyle(Piperly.Colors.textSecondary)
        }
        .listRowBackground(Piperly.Colors.surface)
    }

    // MARK: - PIN Flows

    private func setPINFlow() -> some View {
        PINFlowView(
            step: .setNew,
            onCancel: { showSetPIN = false },
            onComplete: { pin in
                pinManager.setPIN(pin)
                showSetPIN = false
            }
        )
    }

    private func changePINFlow() -> some View {
        PINFlowView(
            step: .verifyCurrent,
            pinManager: pinManager,
            onCancel: { showChangePIN = false },
            onComplete: { pin in
                pinManager.setPIN(pin)
                showChangePIN = false
            }
        )
    }

    private func removePINFlow() -> some View {
        ZStack {
            Piperly.Colors.background.ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        showRemovePIN = false
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
                title: "Enter Current PIN",
                subtitle: "Verify to remove PIN"
            ) { pin in
                if pinManager.verifyPIN(pin) {
                    pinManager.removePIN()
                    showRemovePIN = false
                }
            }
        }
    }

    // MARK: - Server Config

    private func loadServerConfig() {
        if let config = OPDSServerConfig.load() {
            serverURL = config.url.absoluteString
            username = config.username
            password = config.password
        }
    }

    private func saveServerConfig() {
        guard let url = URL(string: serverURL) else { return }
        let config = OPDSServerConfig(url: url, username: username, password: password)
        try? config.save()
    }

    private func testConnection() {
        connectionStatus = .testing
        guard let url = URL(string: serverURL) else {
            connectionStatus = .failed("Invalid URL")
            return
        }

        Task { @MainActor in
            let config = OPDSServerConfig(url: url, username: username, password: password)
            var request = URLRequest(url: url)
            if let authValue = config.authorizationHeaderValue() {
                request.setValue(authValue, forHTTPHeaderField: "Authorization")
            }

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    connectionStatus = .success
                } else {
                    connectionStatus = .failed("Server returned an error")
                }
            } catch {
                connectionStatus = .failed("Could not connect")
            }
        }
    }
}

// MARK: - PIN Flow View (Set / Change)

private struct PINFlowView: View {
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
