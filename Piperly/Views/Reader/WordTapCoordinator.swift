import Foundation
import WebKit
import Combine

class WordTapCoordinator: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var lastTappedWord: String?
    var onWordTapped: ((String) -> Void)?

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "wordTapped",
              let body = message.body as? [String: Any],
              let word = body["word"] as? String else { return }
        lastTappedWord = word
        onWordTapped?(word)
    }
}
