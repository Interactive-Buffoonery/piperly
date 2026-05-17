# Piperly Roadmap

Piperly is an iPad ebook reader for kids. Tap a word, hear it spoken, and keep
reading in a calm, parent-managed environment.

This roadmap is intentionally public-facing. It tracks broad product direction
without internal release notes, private account details, or implementation
scratch work.

## Current Focus

- Keep EPUB reading reliable on supported iPads.
- Preserve the parent-gated OPDS catalog flow.
- Improve first-run setup, accessibility, and App Store readiness.
- Keep the repository easy for contributors to build with their own Apple
  developer account.

## Near-Term Work

- Harden parent controls around catalog access and server configuration.
- Continue release-readiness checks for privacy, launch screen behavior, and
  App Store metadata.
- Expand regression coverage for reading, catalog browsing, and local library
  behavior.
- Polish contributor setup docs as the build process changes.

## Later Ideas

- Add more child-friendly reading progress affordances.
- Improve saved-word review flows.
- Explore additional import and catalog workflows after the core EPUB path is
  stable.
- Revisit voice and speech settings based on real-device testing.

## Non-Goals

- Piperly does not operate a hosted book catalog or proxy OPDS traffic.
- Piperly does not collect analytics, tracking data, or account data.
- This repository should not contain local signing identities, provisioning
  profiles, private service credentials, or internal release-operation notes.
