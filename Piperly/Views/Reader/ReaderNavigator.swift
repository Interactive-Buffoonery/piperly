import SwiftUI
import UIKit
import ReadiumShared
import ReadiumNavigator
import WebKit

struct ReaderNavigator: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocator: Locator?
    let wordTapCoordinator: WordTapCoordinator
    var onProgressChanged: ((Double) -> Void)?
    var onNavigatorReady: ((EPUBNavigatorViewController) -> Void)?
    var onLocationChanged: ((Locator) -> Void)?

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        let prefs = EPUBPreferences(
            backgroundColor: ReadiumNavigator.Color(hex: "#1C1C2E"),
            hyphens: false,
            lineHeight: 1.7,
            publisherStyles: false,
            scroll: false,
            textColor: ReadiumNavigator.Color(hex: "#E8E8F0")
        )

        let config = EPUBNavigatorViewController.Configuration(
            preferences: prefs,
            editingActions: []
        )

        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocator,
                config: config
            )
            navigator.delegate = context.coordinator
            context.coordinator.parent.onNavigatorReady?(navigator)
            return navigator
        } catch {
            // Return a bare navigator as fallback - this shouldn't happen
            // since we already validated the publication
            return try! EPUBNavigatorViewController(
                publication: publication,
                initialLocation: nil
            )
        }
    }

    func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    class Coordinator: NSObject, EPUBNavigatorDelegate {
        let parent: ReaderNavigator

        init(parent: ReaderNavigator) {
            self.parent = parent
        }

        func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
            userContentController.add(parent.wordTapCoordinator, name: "wordTapped")

            if let cssURL = Bundle.main.url(forResource: "reader-theme", withExtension: "css"),
               let css = try? String(contentsOf: cssURL, encoding: .utf8) {
                let escapedCSS = css.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")
                let cssScript = """
                (function() {
                    var style = document.createElement('style');
                    style.textContent = `\(escapedCSS)`;
                    document.head.appendChild(style);
                })();
                """
                userContentController.addUserScript(
                    WKUserScript(source: cssScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
                )
            }

            if let jsURL = Bundle.main.url(forResource: "word-tap", withExtension: "js"),
               let js = try? String(contentsOf: jsURL, encoding: .utf8) {
                userContentController.addUserScript(
                    WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
                )
            }
        }

        func navigator(_ navigator: any Navigator, presentError error: NavigatorError) {}

        nonisolated func navigator(_ navigator: any Navigator, locationDidChange locator: Locator) {
            let progression = locator.locations.totalProgression ?? 0
            Task { @MainActor in
                parent.onProgressChanged?(progression)
                parent.onLocationChanged?(locator)
            }
        }
    }
}
