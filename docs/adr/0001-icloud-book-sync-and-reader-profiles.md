# iCloud book sync and reader profiles

Status: accepted

Piperly will sync user-imported EPUB files, book metadata, covers, words, bookmarks, progress, and reader settings across a family's devices through the user's private iCloud account. Book files are shared at the family/account level, while reading state is scoped to individual reader profiles so children sharing an iPad or Apple account do not overwrite each other's progress or word collections.

## Context

Piperly is a kids ebook reader whose current data model keeps imported EPUB files and derived covers in local app storage, while book metadata, reading progress, bookmarks, and saved words are stored locally in `UserDefaults`. The product direction is to let a family import a book once and read it across all devices, without adding a hosted catalog, social sharing, external accounts, third-party analytics, or third-party storage.

Kids Category compliance shapes the design. iCloud is allowed for a kids app when the sync is private, child data is treated carefully, and parent-facing controls remain gated, but Piperly should not infer or assert content ownership beyond the user's choice to import a file they are allowed to use.

## Decision

Piperly will make iCloud sync a private, family/account-scoped feature:

- **Shared library data**: imported EPUB files, book metadata, derived covers, and file availability state.
- **Per-profile reading data**: last-read location, bookmarks, saved words, voice preferences, reader theme, and future child-specific reading affordances.
- **Default profile**: existing and first-run installs get a single default reader profile named "Reader" so the app remains usable without setup.
- **Parent-managed controls**: profile management and iCloud sync settings belong in parent-facing settings, not in the reading flow.
- **Minimal child information**: profiles use nicknames, avatar symbols, and colors; avoid birthdates, full names, photos, email addresses, or other unnecessary personal information.

## Considered Options

- **Single shared reading state**: simplest, but bad for families because one child can overwrite another child's progress, bookmarks, and words.
- **Sync only progress/words/bookmarks**: lower engineering risk, but fails the chosen product direction because each device would still need every book imported manually.
- **Hosted Piperly account sync**: more control, but creates account, backend, child-data, and operational burdens that are unnecessary for the current product.

## Consequences

Book identity must become stable across devices, likely by hashing EPUB contents during import. The sync implementation must handle iCloud file availability, download progress, evicted files, deletion semantics, and conflicts. Privacy review and App Store privacy answers must be updated once iCloud sync is enabled because book titles, reading state, and saved words are child-adjacent data even when they remain in the user's private iCloud account.
