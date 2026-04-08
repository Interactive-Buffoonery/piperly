# Piperly: Implementation Plan

An iPad ebook reader for kids. Tap a word, hear it spoken. Choose your voice.

## Color Palette

From `color-palette.html` — dark theme, navy-charcoal base.

### Surfaces
| Token | Hex | Usage |
|---|---|---|
| `background` | `#1C1C2E` | App background, deep navy-charcoal |
| `surface` | `#252540` | Cards, panels, bottom sheets |
| `surfaceElevated` | `#2E2E4A` | Hover/selected states, active elements |
| `border` | `#3A3A55` | Subtle borders, dividers |

### Text
| Token | Hex | Usage |
|---|---|---|
| `textPrimary` | `#E8E8F0` | Body text, headings — near-white with warmth |
| `textSecondary` | `#9090A8` | Labels, metadata, timestamps |
| `textTertiary` | `#606078` | Disabled, hints, placeholder |

### Semantic
| Token | Hex | Usage |
|---|---|---|
| `accent` | `#7C9FD4` | Links, selected items, primary actions |
| `success` | `#7BC8A4` | Positive states |
| `warning` | `#D4A76A` | Attention needed |
| `error` | `#D47C7C` | Errors |
| `info` | `#9B8EC4` | Informational badges |

### Extended Palette (charts, voice avatars, decorative)
| Hex | |
|---|---|
| `#7CD4C8` | Teal |
| `#C8A87B` | Tan |
| `#8BC47B` | Green |

---

## Architecture Overview

```
+-------------------------------------------------------+
|                    SwiftUI App                         |
|                                                       |
|  +----------------+  +-----------------------------+  |
|  |   Library View  |  |       Reader View           |  |
|  |                 |  |                             |  |
|  |  Book grid/list |  |  Readium EPUB Navigator     |  |
|  |  Import books   |  |  (UIViewControllerRep.)     |  |
|  |  Reading prog.  |  |                             |  |
|  +--------+--------+  |  +----------------------+   |  |
|           |            |  |  WKWebView (Readium) |   |  |
|           +----------->|  |                      |   |  |
|                        |  |  Injected JS:        |   |  |
|                        |  |  - Word wrapping     |   |  |
|                        |  |  - Tap handler       |   |  |
|                        |  +-----+----------------+   |  |
|                        |        |                    |  |
|                        |        | WKScriptMessage    |  |
|                        |        v                    |  |
|                        |  +-----+----------------+   |  |
|                        |  |  TTS Engine           |   |  |
|                        |  |  sherpa-onnx + Kokoro |   |  |
|                        |  |  Voice picker         |   |  |
|                        |  +-----------------------+   |  |
|                        +-----------------------------+  |
+-------------------------------------------------------+
```

---

## Dependencies

| Package | Source | Purpose |
|---|---|---|
| [Readium Swift Toolkit](https://github.com/readium/swift-toolkit) | SPM | EPUB parsing, rendering, pagination |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | SPM | On-device TTS engine |
| Kokoro-82M v1.0 multi-lang | Bundled model files | Neural TTS model (54 voices, 9 languages) |

No other external dependencies. Everything else is Apple frameworks (SwiftUI, AVFoundation, WebKit).

---

## Phase 1: Project Scaffold + Book Rendering

**Goal:** Open an EPUB and read it with Readium in a SwiftUI app on iPad.

### 1.1 Xcode Project Setup
- Create a new Xcode project: `Piperly`, iOS App, SwiftUI lifecycle
- Deployment target: iPadOS 17.0 (covers all iPads from 2018+)
- Add SPM dependencies:
  - `ReadiumShared`, `ReadiumStreamer`, `ReadiumNavigator` from `https://github.com/readium/swift-toolkit`
- Create an `Assets.xcassets` color set matching the palette above
- Define a `PiperlyTheme` enum with all color/typography tokens as SwiftUI `Color` and `Font` extensions

### 1.2 Color System
```swift
// Theme.swift
enum Piperly {
    enum Colors {
        static let background = Color(hex: 0x1C1C2E)
        static let surface = Color(hex: 0x252540)
        static let surfaceElevated = Color(hex: 0x2E2E4A)
        static let border = Color(hex: 0x3A3A55)

        static let textPrimary = Color(hex: 0xE8E8F0)
        static let textSecondary = Color(hex: 0x9090A8)
        static let textTertiary = Color(hex: 0x606078)

        static let accent = Color(hex: 0x7C9FD4)
        static let success = Color(hex: 0x7BC8A4)
        static let warning = Color(hex: 0xD4A76A)
        static let error = Color(hex: 0xD47C7C)
        static let info = Color(hex: 0x9B8EC4)
    }

    enum Typography {
        static let title = Font.system(size: 24, weight: .bold, design: .rounded)
        static let body = Font.system(size: 18, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 14, weight: .medium, design: .rounded)
    }
}
```

### 1.3 Data Layer
- `BookStore` class (ObservableObject) — manages imported EPUBs
  - Store books in app's Documents directory
  - Track reading position per book (chapter + progression %) via `UserDefaults` or a lightweight JSON file
  - Parse EPUB metadata (title, author, cover image) via Readium's `Publication` model
- Support importing EPUBs via:
  - Files app (document picker — `UIDocumentPickerViewController`)
  - Drag and drop on iPad
  - Bundle a few sample/public-domain EPUBs for first launch

### 1.4 Library View
- Grid of book covers on `background` (#1C1C2E)
- Each book card: cover image, title, author, reading progress bar
- Card background: `surface` (#252540), border: `border` (#3A3A55)
- Progress bar: `accent` (#7C9FD4)
- "Add Book" button: `accent` with `surfaceElevated` background
- Tap a book to open the Reader View

### 1.5 Reader View (Readium Integration)
- Wrap Readium's `EPUBNavigatorViewController` in `UIViewControllerRepresentable`
  - Follow [Readium's SwiftUI guide](https://github.com/readium/swift-toolkit/blob/develop/docs/Guides/Navigator/SwiftUI.md)
- Configure pagination mode (not scrolling) for a book-like feel
- Inject CSS for our theme into Readium's navigator:
  ```css
  body {
      background: #1C1C2E !important;
      color: #E8E8F0 !important;
      font-size: 22px !important;
      line-height: 1.7 !important;
      hyphens: none !important;
      max-width: 35em;
      margin: 0 auto;
  }
  ```
- Page turn via swipe gestures (Readium handles this)
- Top toolbar (slide down to reveal): book title, back button, settings gear
- Bottom: page indicator (e.g., "Page 12 of 45" or chapter progress)

### Phase 1 Milestone
**Can open an EPUB, see it rendered with our dark theme, and turn pages on an iPad.**

---

## Phase 2: Word-Level Tap Detection

**Goal:** Tap any word in the book and know which word was tapped.

### 2.1 JavaScript Injection via `setupUserScripts`

Implement `EPUBNavigatorDelegate` and use the `setupUserScripts` hook:

```swift
func navigator(
    _ navigator: EPUBNavigatorViewController,
    setupUserScripts userContentController: WKUserContentController
) {
    // Register handler for word taps
    userContentController.add(coordinator, name: "wordTapped")

    // Inject word-wrapping script
    let script = WKUserScript(
        source: Self.wordTapJS,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )
    userContentController.addUserScript(script)
}
```

### 2.2 Word-Wrapping JavaScript

```javascript
(function() {
    const WORD_CLASS = 'piperly-word';

    function wrapTextNode(textNode) {
        const text = textNode.textContent;
        if (!text.trim()) return;

        const fragment = document.createDocumentFragment();
        // Split on word boundaries, preserving whitespace
        const parts = text.split(/(\s+)/);
        parts.forEach(part => {
            if (/\s+/.test(part)) {
                fragment.appendChild(document.createTextNode(part));
            } else if (part.length > 0) {
                const span = document.createElement('span');
                span.className = WORD_CLASS;
                span.textContent = part;
                fragment.appendChild(span);
            }
        });
        textNode.parentNode.replaceChild(fragment, textNode);
    }

    function wrapAllWords() {
        const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            {
                acceptNode: function(node) {
                    // Skip script, style, and already-wrapped content
                    const tag = node.parentElement.tagName;
                    if (tag === 'SCRIPT' || tag === 'STYLE') return NodeFilter.FILTER_REJECT;
                    if (node.parentElement.classList.contains(WORD_CLASS)) return NodeFilter.FILTER_REJECT;
                    if (!node.textContent.trim()) return NodeFilter.FILTER_REJECT;
                    return NodeFilter.FILTER_ACCEPT;
                }
            }
        );

        const textNodes = [];
        while (walker.nextNode()) textNodes.push(walker.currentNode);
        textNodes.forEach(wrapTextNode);
    }

    // Style tapped words with a brief highlight
    const style = document.createElement('style');
    style.textContent = `
        .${WORD_CLASS} { cursor: pointer; border-radius: 3px; transition: background 0.15s; }
        .${WORD_CLASS}.tapped { background: rgba(124, 159, 212, 0.3); }
    `;
    document.head.appendChild(style);

    // Tap handler — does NOT stopPropagation (preserves Readium page turning)
    document.addEventListener('click', function(e) {
        const target = e.target;
        if (target.classList.contains(WORD_CLASS)) {
            // Strip punctuation for cleaner TTS
            const raw = target.textContent;
            const clean = raw.replace(/^[^a-zA-Z\u00C0-\u024F]+|[^a-zA-Z\u00C0-\u024F]+$/g, '');
            if (clean.length === 0) return;

            // Visual feedback
            target.classList.add('tapped');
            setTimeout(() => target.classList.remove('tapped'), 400);

            // Send to Swift
            window.webkit.messageHandlers.wordTapped.postMessage({
                word: clean,
                raw: raw,
                rect: target.getBoundingClientRect()
            });
        }
    });

    wrapAllWords();

    // Re-wrap after Readium dynamic content changes
    const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
            mutation.addedNodes.forEach(function(node) {
                if (node.nodeType === Node.ELEMENT_NODE && !node.classList.contains(WORD_CLASS)) {
                    const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
                    const textNodes = [];
                    while (walker.nextNode()) textNodes.push(walker.currentNode);
                    textNodes.forEach(wrapTextNode);
                }
            });
        });
    });
    observer.observe(document.body, { childList: true, subtree: true });
})();
```

### 2.3 Swift Message Handler

```swift
class WordTapCoordinator: NSObject, WKScriptMessageHandler {
    var onWordTapped: ((String) -> Void)?

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "wordTapped",
              let body = message.body as? [String: Any],
              let word = body["word"] as? String else { return }
        onWordTapped?(word)
    }
}
```

### 2.4 Visual Feedback
- Tapped word gets a brief `accent` (#7C9FD4) background highlight (0.3 alpha, 400ms fade)
- Optional: show a small tooltip/bubble above the word with the pronunciation (stretch goal)

### Phase 2 Milestone
**Tap any word in the book and see it highlighted. The word string arrives in Swift.**

---

## Phase 3: Text-to-Speech with Voice Selection

**Goal:** Tapped words are spoken aloud using Kokoro neural TTS with selectable voices.

### 3.1 sherpa-onnx + Kokoro Setup
- Add sherpa-onnx via SPM: `https://github.com/k2-fsa/sherpa-onnx`
- Bundle Kokoro v1.0 multi-lang model files in the app:
  - `model.onnx` (~80-100 MB)
  - `voices.bin` (all 54 voice embeddings)
  - `tokens.txt`
  - `espeak-ng-data/` directory
  - Lexicon files for each language
- Create a `TTSEngine` actor that:
  - Initializes the model once at app launch
  - Exposes `func speak(word: String, voiceID: Int, speed: Float)` 
  - Manages `AVAudioSession` configuration
  - Handles interruption (if a new word is tapped while speaking, stop and speak the new one)

### 3.2 Voice Model

```swift
struct Voice: Identifiable, Codable {
    let id: Int          // sherpa-onnx speaker ID
    let name: String     // display name (e.g., "Heart")
    let language: String // e.g., "en-US", "en-GB"
    let gender: Gender
    let grade: Grade     // quality tier

    enum Gender: String, Codable { case female, male }
    enum Grade: String, Codable { case a, b, c }
}
```

Curated voice list (hide low-quality voices from kids):

| Display Name | sid | Gender | Accent | Why included |
|---|---|---|---|---|
| Heart | 3 | F | American | Best overall (Grade A) |
| Bella | 2 | F | American | Second best (Grade A-) |
| Nicole | 6 | F | American | Distinct personality (Grade B-) |
| Emma | 21 | F | British | British accent for variety (Grade B-) |
| Puck | 18 | M | American | Best male, playful name (Grade C+) |
| Fenrir | 14 | M | American | Adventure vibes (Grade C+) |
| Michael | 16 | M | American | Neutral male (Grade C+) |

### 3.3 Voice Picker UI
- Accessible from a toolbar button in the Reader View (speaker icon)
- Bottom sheet (`surface` #252540 background) with voice cards
- Each voice card:
  - Background: `surfaceElevated` (#2E2E4A) when selected, `surface` otherwise
  - Name in `textPrimary`, language/gender in `textSecondary`
  - Colored avatar circle using the extended palette (#7C9FD4, #7BC8A4, #9B8EC4, etc.) — each voice gets a unique color
  - Tap a voice card to hear a preview ("Hi, I'm Heart!")
  - Selected voice has an `accent` (#7C9FD4) border/checkmark
- Selected voice persisted in `UserDefaults`

### 3.4 Wiring It Together
```
Word tapped in WKWebView
  -> JS posts message to Swift
  -> WordTapCoordinator receives word
  -> TTSEngine.speak(word: "dinosaur", voiceID: selectedVoice.id, speed: 0.9)
  -> Audio plays through device speakers
```

### 3.5 Audio Session
```swift
try AVAudioSession.sharedInstance().setCategory(
    .playback,
    mode: .spokenContent,
    options: [.duckOthers]
)
```

### Phase 3 Milestone
**Tap a word, hear it spoken in a natural voice. Switch between 7 curated voices.**

---

## Phase 4: Kid-Friendly Polish

**Goal:** Make the app delightful for a 10-year-old.

### 4.1 Typography for the Reader
- Default font size: 22px (adjustable 18-30px via settings)
- Line height: 1.7x
- Word spacing: slightly increased (+0.5px)
- Hyphenation: OFF
- Font: system (San Francisco) — highly legible, or allow New York (serif) as option
- Max content width: 35em, centered
- All controlled via CSS injection into Readium

### 4.2 Reading Settings
- Accessible via gear icon in reader toolbar
- Bottom sheet with:
  - Font size slider (18-30px)
  - Font choice: Sans-serif / Serif toggle
  - Speed slider for TTS voice (0.6x - 1.2x)
- Settings persisted per-book or globally (user's choice)

### 4.3 First-Launch Experience
- Bundle 2-3 public domain children's books (e.g., from Project Gutenberg / Standard Ebooks):
  - Alice in Wonderland
  - The Jungle Book
  - A fairy tale collection
- Brief onboarding: "Tap any word to hear it!" with an animated hand tapping a word

### 4.4 Reading Progress
- Track last position per book (Readium's `Locator`)
- Progress bar on each book in the library (% complete)
- "Continue Reading" prominent on the library screen for the last-opened book

### 4.5 iPad Layout
- Support all orientations — re-paginate on rotation
- In landscape on larger iPads: optionally show two-page spread
- Respect readable content width in all orientations
- Support keyboard shortcuts: arrow keys for page turning

### Phase 4 Milestone
**The app feels polished, welcoming, and easy for a 10-year-old to use independently.**

---

## Phase 5: Stretch Goals

These are ideas for later, not blocking the initial release.

- **Word history**: Track words she's tapped — build a personal vocabulary list
- **Dictionary popup**: Show a simple definition alongside the pronunciation
- **Sentence mode**: Long-press a word to hear the full sentence read aloud
- **Voice blending**: Pre-compute custom voice blends in Python, bundle as extra voices
- **Reading streaks**: Light gamification — days read in a row, books finished
- **Multiple profiles**: If siblings also want to use it, separate progress/voice prefs
- **Bookmarks and highlights**: Tap-and-hold to highlight passages

---

## File Structure

```
Piperly/
  Piperly.xcodeproj
  Piperly/
    App/
      PiperlyApp.swift              # App entry point
      ContentView.swift             # Root navigation (library vs reader)
    Theme/
      Colors.swift                  # Color tokens from palette
      Typography.swift              # Font definitions
    Models/
      Book.swift                    # Book metadata model
      Voice.swift                   # Voice model + curated list
      ReadingProgress.swift         # Position tracking
    Services/
      BookStore.swift               # EPUB import, storage, metadata
      TTSEngine.swift               # sherpa-onnx wrapper, audio session
    Views/
      Library/
        LibraryView.swift           # Book grid
        BookCard.swift              # Individual book card
        ImportButton.swift          # Document picker trigger
      Reader/
        ReaderView.swift            # Main reader screen
        ReaderNavigator.swift       # Readium UIViewControllerRepresentable
        ReaderToolbar.swift         # Top bar (back, title, settings, voice)
        WordTapCoordinator.swift    # WKScriptMessageHandler bridge
      Settings/
        VoicePickerSheet.swift      # Voice selection bottom sheet
        ReadingSettingsSheet.swift  # Font size, font choice, TTS speed
    Resources/
      word-tap.js                   # Word-wrapping + tap handler JS
      reader-theme.css              # Dark theme CSS for Readium
      Models/
        kokoro-v1.0/                # Bundled TTS model files
          model.onnx
          voices.bin
          tokens.txt
          espeak-ng-data/
      SampleBooks/                  # Bundled public domain EPUBs
  PiperlyTests/
  PiperlyUITests/
```

---

## Build Sequence

| Order | What | Depends On | Est. Complexity |
|---|---|---|---|
| 1 | Xcode project + SPM deps + color system | Nothing | Low |
| 2 | BookStore + EPUB import | (1) | Medium |
| 3 | Library View | (1), (2) | Medium |
| 4 | Readium integration + Reader View | (1), (2) | Medium-High |
| 5 | CSS theme injection | (4) | Low |
| 6 | JS word wrapping + tap detection | (4) | Medium |
| 7 | sherpa-onnx + Kokoro setup | (1) | Medium |
| 8 | Wire word tap to TTS | (6), (7) | Low |
| 9 | Voice picker UI | (7), (1) | Medium |
| 10 | Reading settings (font size, speed) | (4), (7) | Low |
| 11 | Reading progress persistence | (4) | Low |
| 12 | First-launch + sample books | (3), (4) | Low |
| 13 | iPad layout polish | All above | Low-Medium |

Steps 2+3 and 6+7 can be worked in parallel.

---

## Key Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| sherpa-onnx Kokoro crash on iOS ([#1968](https://github.com/k2-fsa/sherpa-onnx/issues/1968)) | TTS doesn't work | Test early in Phase 3. Fallback: FluidAudio (CoreML) or AVSpeechSynthesizer |
| JS word wrapping breaks Readium page turning | Reader unusable | Don't call `stopPropagation()`. Test with multiple EPUB layouts. Keep Readium's gesture pipeline intact |
| Kokoro model size (~100 MB) inflates app | App Store size limit concern | 100 MB is well within limits. Could use on-demand resources if needed |
| Memory pressure from Kokoro on older iPads | App crashes | Test on oldest supported iPad (A10 chip). Kokoro ~500 MB RAM — should fit. Fallback: AVSpeechSynthesizer for low-memory devices |
| EPUB CSS conflicts with injected theme | Ugly rendering | Use `!important` selectively. Test with varied EPUBs. Readium's CSS handling is robust |
