# Piperly

Piperly is a parent-managed ebook reader for children. Its language separates shared family library data from per-child reading data so sync behavior stays predictable.

## Language

**Book File**:
The user-imported EPUB file that Piperly stores and syncs as family/account-level library data.
_Avoid_: Owned book, purchase

**Book Metadata**:
Descriptive data derived from or attached to a Book File, such as title, author, cover reference, stable content identity, and file availability.
_Avoid_: Reading state

**Reader Profile**:
A lightweight child-facing reading identity within Piperly, identified by a nickname, avatar symbol, and color.
_Avoid_: Account, user account, child account

**Reading State**:
Per-profile data created while reading, including current position, bookmarks, saved words, and reader preferences.
_Avoid_: Book metadata, shared state

**Shared Library**:
The family/account-level collection of synced Book Files and Book Metadata available to every Reader Profile.
_Avoid_: Catalog, bookstore
