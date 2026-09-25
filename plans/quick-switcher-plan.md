# Quick switcher implementation plan

## Goal and scope

Implement a keyboard-first quick switcher for vMini. Press **⌘P**, type part of a filename, and
press **Enter** to switch to an open document or reopen a recent file.

Search **only open tabs and the application's recent files**. Include open untitled documents. Do
not enumerate sidebar folders, search document contents, query Spotlight, or build a filesystem
index. Pinned tabs, preview tabs, command execution, and a general command palette are outside this
task.

This is a personal-use native macOS editor with recent responsiveness improvements. Keep the
implementation small, preserve the existing asynchronous file-opening path, and add no dependencies.

## User-visible behavior

1. Add **File → Quick Switcher…**, with **⌘P**. Enable it when a workspace window can present it,
   including when no document is open. Do not present over an existing unrelated sheet.
2. Present a compact native search popup attached to the workspace. For this version, use an AppKit
   sheet following the existing Go to Line presentation pattern; a custom floating-window system is
   unnecessary. Focus the search field immediately.
3. Start with an empty query and the default result order described below. Reopening resets the
   query. Invoking the command while the switcher is already visible focuses its existing search
   field rather than presenting another instance.
4. Show filename or document title as the primary text, an abbreviated parent-directory path as
   secondary text, and an **Open** or **Recent** label. Use **Unsaved document** as the secondary
   text for untitled tabs. Distinct untitled documents must remain separate selectable rows.
5. Typing filters the list immediately. Select the first result after a query change. Show about
   eight rows, with scrolling for additional results; every match must remain reachable.
6. **Up/Down** moves the selection without moving focus out of the search field. Clamp at the
   first/last row. **Enter** activates the selection; double-clicking a row does the same.
   Single-clicking selects a row without opening it.
7. **Escape** dismisses the switcher and restores the previous first responder, selection, and
   scroll position. Browsing results must never activate or preview documents.
8. Show **No matching files** for an unmatched query and **No open or recent files** for an empty
   candidate set. Enter does nothing when there is no selected result.
9. Dismiss the sheet before routing an activation, so an opening-error sheet can appear normally.
   After successful activation, the destination editor should receive keyboard focus.

Example:

```text
Search open tabs and recent files
> sett

settings.json          ~/Projects/myapp     Open
settings.local.json    ~/Projects/myapp     Recent
```

## Candidate data and identity

- Get open documents from `OpenDocumentsStore`; use `Document.shortDisplayTitle`, `fileURL`, and
  `sessionIdentifier`. Read metadata only: do not request document contents or create editor
  controllers while building results.
- Get recent URLs from `NSDocumentController.shared.recentDocumentURLs`. Reuse this existing
  history; do not introduce another persisted recent-files list.
- Deduplicate saved files using `standardizedFileURL`, consistent with existing document routing. If
  a URL is both open and recent, show the open document once. Do not lowercase paths for identity or
  resolve symlinks during filtering.
- Identify untitled documents by `sessionIdentifier`, never by their displayed title.
- Snapshot recent URLs when presenting. Observe open-document changes only while the switcher is
  visible, rebuilding candidates when tabs close, open, or change their titles/URLs. Preserve the
  selected identity if it still matches; otherwise select the first result. Remove the observation
  on dismissal.
- Do not synchronously probe every recent URL for existence. Missing or inaccessible recent entries
  may appear; selecting one must use the existing open-error handling. Do not silently clear the
  user's recent history.
- Clear temporary candidate references on dismissal so the switcher does not retain closed
  documents.

## Ordering and matching

Use simple case-insensitive, literal filename/title matching. Do not add regex, fuzzy subsequence
matching, path queries, or relevance libraries in this version.

### Empty query

1. Previously activated open documents, most recently activated first, excluding the current
   document.
2. Other open documents without activation history, in existing tab order.
3. The current document, if any.
4. Recent files that are not open, preserving the order supplied by `recentDocumentURLs`.

This makes **⌘P → Enter** return to the previous open document when one exists. The current document
remains searchable and selectable.

Track activation order in memory in `OpenDocumentsStore`, independently of the visual tab order. Use
document identifiers rather than a second collection retaining documents. Update only when the
active document actually changes, covering selection, activation during registration, and the
fallback selection after closing a tab. Remove closed identifiers. Refresh notifications and tab
dragging must not alter activation order. Do not persist this history across launches; tab order is
the fallback until documents are activated.

### Nonempty query

Trim surrounding whitespace. Rank matching candidates by:

1. Exact filename/title match.
2. Filename/title prefix match.
3. Filename/title substring match.

Within each tier, preserve the empty-query order. Thus an exact recent-file match beats a partial
open-tab match. The secondary path distinguishes duplicate names visually but is not searched.
Handle Unicode safely using Swift/Foundation string operations rather than manual UTF-16 offsets.

## Existing integration points

Read the repository's `AGENTS.md` and use CodeGraph before locating or changing code. The following
are the relevant existing components; verify their current implementations before editing:

| Component                                                                                   | Integration                                                                                                                          |
|---------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| `vmini/Application/Menu/MenuBuilder.swift`                                                  | Add the File menu item and shortcut.                                                                                                 |
| `vmini/Application/Commands/AppCommandDispatcher.swift`                                     | Add the action, validation, and lazily owned switcher controller. Follow the existing Go to Line construction pattern.               |
| `vmini/Application/Commands/ActiveWorkspaceResolver.swift`                                  | Resolve and capture the workspace host before showing the sheet. While a sheet is key, `activeWindow()` can return the sheet itself. |
| `vmini/Features/GoToLine/GoToLineWindowController.swift` and `GoToLineViewController.swift` | Reuse the native sheet lifecycle, focus, theme, and cancellation conventions.                                                        |
| `vmini/Features/Workspace/Documents/OpenDocumentsStore.swift`                               | Source of open documents and activation history. Keep tab order unchanged.                                                           |
| `vmini/Features/Workspace/Window/WorkspaceDocumentCoordinator.swift`                        | Existing `WorkspaceDocumentRouting.present(document:)` and `open(urls:activate:)` activation paths.                                  |
| `vmini/Features/Workspace/Window/WorkspaceDocumentOpener.swift`                             | Existing asynchronous loading and duplicate-open handling; retain this path.                                                         |
| `vmini.xcodeproj/project.pbxproj`                                                           | Register every new application Swift file in the appropriate group and Sources build phase.                                          |

Activation must go through the existing document router. For an open result, revalidate that the
document is still registered, then call `present(document:)`; do not merely select the store or
create a replacement document. For a recent result, check whether the URL is now open and present
that document if so; otherwise call `open(urls:activate:)`. If an open result has disappeared,
refresh the results rather than resurrecting its stale document object. Use the existing failure
presentation for missing or unreadable recent files.

## Implementation sequence

1. **Add activation history and candidate logic.** Keep candidate construction, deduplication,
   filtering, and ranking separate from AppKit view code. A small candidate value type and concrete
   helper in `Features/QuickSwitcher/QuickSwitcherModel.swift` are sufficient; no new service
   protocols or generalized search framework.
2. **Add native UI.** Use `NSSearchField`, `NSTableView`, and `NSScrollView` in
   `QuickSwitcherViewController.swift`, with sheet ownership in
   `QuickSwitcherWindowController.swift`. Follow the project's single-responsibility convention. Use
   existing theme colors, native selection rendering, accessibility labels, and keyboard command
   handling that respects text input composition.
3. **Wire the command and routing.** Add the menu action and lazy controller ownership. Pass the
   existing document router and store through the project's current dependency-injection style where
   needed. Capture the parent window before presenting; release callbacks and observation tokens on
   dismissal. Prevent duplicate activation from repeated Enter presses.
4. **Register sources and validate.** Add application files to the Xcode project, add targeted
   regression coverage, and run the checks below. Do not change editor layout, highlighting,
   watchers, session persistence, or save/close behavior to implement the switcher.

Filtering this small metadata collection synchronously is sufficient. Cache normalized matching
strings for the current candidate snapshot if useful. Do not debounce keystrokes, launch a task per
character, perform file reads, load file-specific icons, or do filesystem scans in the filtering
path.

## Validation and acceptance criteria

Add focused XCTest coverage using the existing test target:

- Candidate merging: open/recent duplicates collapse; same basename in different directories stays
  distinct; multiple untitled documents remain distinct.
- Matching: exact before prefix before substring, case-insensitivity, whitespace-only query, Unicode
  names, no matches, and stable ordering within a tier.
- Activation history: selecting A → B → C makes B the default switcher result; reorder/refresh does
  not change history; closing a document removes its identifier; initial documents fall back to tab
  order.
- Routing: selecting an existing document preserves its identity and unsaved state; recent selection
  uses the existing open path; a recent file opened while the popup is visible does not create
  another tab; a stale open result is not re-registered.
- Lifecycle: cancellation performs no routing, reopening creates no duplicate observation, and
  repeated activation cannot submit twice. Use existing routing test doubles where practical rather
  than filesystem fixtures for every case.

Manually verify in the app:

- ⌘P opens and focuses the field; typing, Up/Down, Enter, Escape, clicking, and scrolling work.
- ⌘P → Enter toggles between the last two activated open documents.
- Escape preserves the original editor position and focus; activation focuses the selected editor.
- Duplicate names show enough path context; untitled and modified documents work; a missing recent
  file produces the normal error without hanging or conflicting sheets.
- The command works with no open tabs, remains safe with another sheet open, and does not attach to
  itself when invoked twice.
- Both themes remain readable, and VoiceOver can identify the search field and result rows.
- With a synthetic list of roughly 1,000 candidates, typing remains responsive and triggers no disk
  access or document loading. A large open document must not make opening or filtering the switcher
  slower through content processing.

Run `swift test -c release` after implementation. Run `./scripts/build.sh` once to verify Xcode
source registration, rather than after each edit. Report the actual checks performed and any
remaining limitations.

## Completion

Deliver the working feature and its focused tests. Summarize changed behavior and validation. Do not
implement folder search, content search, pinned tabs, or other proposed features as part of this
plan.
