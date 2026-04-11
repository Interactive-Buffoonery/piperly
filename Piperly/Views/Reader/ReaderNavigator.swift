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
import UIKit
import OSLog
import ReadiumShared
import ReadiumNavigator
import WebKit

private let logger = Logger(subsystem: "com.piperly", category: "ReaderNavigator")

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (any WKScriptMessageHandler)?

    init(delegate: any WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(controller, didReceive: message)
    }
}

struct ReaderNavigator: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocator: Locator?
    let wordTapCoordinator: WordTapCoordinator
    let preferences: EPUBPreferences
    let readerTheme: ReaderTheme
    var onProgressChanged: ((Double) -> Void)?
    var onNavigatorReady: ((EPUBNavigatorViewController) -> Void)?
    var onLocationChanged: ((Locator) -> Void)?

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        let config = EPUBNavigatorViewController.Configuration(
            preferences: preferences,
            editingActions: []
        )

        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocator,
                config: config
            )
            navigator.delegate = context.coordinator
            let callback = onNavigatorReady
            DispatchQueue.main.async {
                callback?(navigator)
            }
            return navigator
        } catch {
            logger.error("EPUBNavigatorViewController init failed: \(error.localizedDescription)")
            do {
                let navigator = try EPUBNavigatorViewController(
                    publication: publication,
                    initialLocation: nil
                )
                navigator.delegate = context.coordinator
                return navigator
            } catch {
                fatalError("Cannot create EPUB navigator for '\(publication.metadata.title ?? "unknown")': \(error.localizedDescription)")
            }
        }
    }

    func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {
        uiViewController.submitPreferences(preferences)
        if readerTheme != context.coordinator.lastTheme {
            context.coordinator.lastTheme = readerTheme
            let script = readerTheme.cssVariablesScript
            Task { @MainActor in
                _ = await uiViewController.evaluateJavaScript(script)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    class Coordinator: NSObject, EPUBNavigatorDelegate {
        let parent: ReaderNavigator
        var lastTheme: ReaderTheme

        init(parent: ReaderNavigator) {
            self.parent = parent
            self.lastTheme = parent.readerTheme
        }

        func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
            userContentController.add(WeakScriptMessageHandler(delegate: parent.wordTapCoordinator), name: "wordTapped")

            userContentController.addUserScript(
                WKUserScript(source: parent.readerTheme.cssVariablesScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            )

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
