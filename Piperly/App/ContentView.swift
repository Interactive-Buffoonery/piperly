import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bookStore: BookStore
    @EnvironmentObject var pinManager: PINManager
    @EnvironmentObject var opdsService: OPDSService
    @State private var selectedBook: Book?
    @State private var selectedTab: ContentTab = .library
    @State private var showingSettings = false
    @State private var showingImporter = false
    @State private var browseUnlocked = false
    @State private var showBrowsePIN = false
    @State private var browsePINKey = UUID()

    let ttsEngine: TTSEngine

    enum ContentTab: String, CaseIterable {
        case library = "My Books"
        case words = "Words"
        case browse = "Browse"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom header
                HStack {
                    Text("Piperly")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Piperly.Colors.accent)

                    Spacer()

                    Picker("", selection: $selectedTab) {
                        ForEach(ContentTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .colorScheme(.dark)
                    .frame(width: 340)

                    Spacer()

                    HStack(spacing: 12) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundStyle(Piperly.Colors.accent)
                        }

                        if selectedTab == .library {
                            Button {
                                showingImporter = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Piperly.Colors.accent)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                switch selectedTab {
                case .library:
                    LibraryView(
                        selectedBook: $selectedBook,
                        showingImporter: $showingImporter
                    )
                case .words:
                    WordsView(ttsEngine: ttsEngine)
                case .browse:
                    CatalogView()
                }
            }
            .background(Piperly.Colors.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $selectedBook) { book in
                ReaderView(book: book, ttsEngine: ttsEngine)
                    .environmentObject(bookStore)
            }
            .pinGated(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(opdsService)
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .browse && pinManager.isPINSet && !browseUnlocked {
                    selectedTab = .library
                    browsePINKey = UUID()
                    showBrowsePIN = true
                }
            }
            .fullScreenCover(isPresented: $showBrowsePIN) {
                ZStack {
                    Piperly.Colors.background.ignoresSafeArea()

                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                showBrowsePIN = false
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
                            browseUnlocked = true
                            showBrowsePIN = false
                            selectedTab = .browse
                        } else {
                            browsePINKey = UUID()
                        }
                    }
                    .id(browsePINKey)
                }
            }
        }
    }
}
