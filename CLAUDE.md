# Piperly

iPad ebook reader for kids. Tap a word, hear it spoken. Dark navy-charcoal theme.

## Build

Project uses XcodeGen (`project.yml`). Regenerate with:
```bash
xcodegen generate
```

Build/run via Xcode -- target `Piperly`, iPad simulator or device (iPadOS 17+, iPad-only).

## Architecture

SwiftUI app with Readium Swift Toolkit 3.2+ for EPUB rendering. Single-window iPad app.

```
Piperly/
  App/           # PiperlyApp entry, ContentView root nav
  Theme/         # Colors + Typography tokens (dark palette)
  Models/        # Book, Voice, ReadingProgress
  Services/      # BookStore (EPUB import/storage), TTSEngine (AVSpeechSynthesizer)
  Views/
    Library/     # Book grid, card, import
    Reader/      # Readium EPUB navigator, word-tap JS bridge, toolbar
    Settings/    # Voice picker, reading settings, first-launch voice setup
  Resources/     # reader-theme.css, word-tap.js
```

## Key Patterns

- **TTS**: Uses `AVSpeechSynthesizer` (not sherpa-onnx -- was replaced). Voice selection
  uses system voice identifiers. PLAN.md still references sherpa-onnx/Kokoro but code diverged.
- **Word tap**: JS injected via Readium's `setupUserScripts` delegate wraps text nodes in
  `<span class="piperly-word">`, sends taps to Swift via `WKScriptMessageHandler`.
  Does NOT call `stopPropagation()` -- preserves Readium's page-turn gestures.
- **Theme injection**: CSS loaded from `reader-theme.css` bundle resource, injected as
  `WKUserScript` at document end.
- **Concurrency**: Swift 6 strict concurrency enabled. TTSEngine is `@MainActor`.
  Navigator delegate uses `nonisolated` + `Task { @MainActor }` for callbacks.

## Readium API Gotchas (v3.2+)

- `DefaultPublicationParser` requires non-optional `pdfFactory:` -- use `DefaultPDFDocumentFactory()`
- `parser.parse(asset:)` needs `warnings:` param -- pass `nil`
- `AssetRetriever.retrieve(url:)` takes `AbsoluteURL` not Foundation `URL` -- use `FileURL(url:)`
- `EPUBNavigatorViewController.init` throws -- wrap in do/catch
- `EPUBNavigatorDelegate` requires explicit `presentError` even though base protocol has default

## Code Style

- Swift 6 with strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- Tabs/spaces: check file before editing
- Self-documenting code preferred over comments
