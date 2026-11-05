# Parquet viewer: basic first release

## Goal

Open a local Parquet file in vMini and explore it through a read-only native table. Support column
sorting, filters configured entirely through the UI, automatic formatting, and a counter showing
matching rows out of total rows. Reuse the existing workspace, tabs, themes, and document routing.

This is an implementation plan, not a completed feature. The initial estimate is **5–10 engineering
days**, including integration and focused validation. A **1–2 day integration spike**, included in
that estimate, should establish whether the proposed dependency and data-loading approach work.
Revisit the estimate after testing representative files; no file-size or latency guarantee has been
established yet.

## First-release scope

- Local files, opened through the existing Open command, Finder routing, drag and drop, sidebar,
  recent files, and session restore where those entry points already exist.
- Read-only viewing. Sorting and filtering change the view, never the source file or document's
  edited state. Disable Save, Save As, and text-editing commands for Parquet documents, and reject
  writes at the document layer as well.
- Native `NSTableView` with resizable columns, horizontal scrolling, selectable rows, and bounded
  row batches. Use simple Previous/Next page controls for the first release rather than building a
  custom infinite-scrolling grid. Start with 1,000 rows per page and validate that choice in the spike.
- One active sort column, with ascending, descending, and clear-sort actions.
- Multiple type-appropriate filters combined with AND, displayed as removable chips. Include a
  Clear Filters action.
- Automatic formatting driven by the file schema. Preserve numeric precision and distinguish NULL
  from empty strings.
- A counter such as **1 of 652 rows · 9 columns**, reporting matches across the entire file. Show
  the displayed page range separately when useful, so page size is never confused with match count.
- Keep view state when switching between open tabs. Reopening the app restores the file through the
  existing session mechanism; persisting filters, sorting, page, and column widths is outside v1.

Exclude SQL input, cell editing, writes, export, global search, multi-column sorting, OR groups,
histograms, pivots, aggregations, cloud URLs, folder datasets, joins, and a nested-value inspector.

## Engine and UI approach

Use **DuckDB through its official Swift package** for schema discovery, Parquet decoding, sorting,
filtering, and counts. Use AppKit for the table and filter controls. Generated SQL is an internal
implementation detail; the UI never asks users to write or understand it.

DuckDB's Parquet reader supports filter and projection pushdown. This can reduce reads, but does not
guarantee that sorting or counting matches will be instant. Do not write a Parquet parser or load the
entire file into an array of Swift row objects.

References:

- [Official DuckDB Swift package](https://github.com/duckdb/duckdb-swift)
- [DuckDB Parquet reader](https://duckdb.org/docs/2.0/data/parquet/overview)
- [Parquet logical types](https://parquet.apache.org/docs/file-format/types/logicaltypes/)

### Integration spike

Implementation and measured results: [DuckDB integration spike](parquet-integration-spike-results.md).
The spike is complete and DuckDB is accepted for the next step. Spike-only app entry points were
removed; the engine connection, fixture, and regression checks remain. Next: the read-only document path.

Before building the complete UI:

1. Pin a compatible DuckDB release and integrate it with both `Package.swift` and the Xcode target.
   Verify compatibility with vMini's macOS 13 deployment target and supported architectures.
2. Verify Parquet support works in a packaged app offline, including required codecs, without
   requiring a user-installed DuckDB executable or a first-run extension download.
3. Open representative small and large files, discover schema, fetch a bounded page, apply a typed
   filter, sort, and count matching rows.
4. Verify the chosen Swift API can cancel long-running work and control resource use. A bounded
   displayed page alone does not bound query-engine memory or sort work.
5. Measure clean-build time, release app-size impact, peak memory, initial display time, and filtered
   sort/count time. Record file dimensions, compression, hardware, and build configuration alongside
   results. Set realistic acceptance targets from the expected files rather than claiming arbitrary
   multi-gigabyte performance.

If the packaged reader, cancellation, or resource behavior fails these checks, resolve that before
committing to the rest of the implementation. Do not silently substitute an external CLI.

## User-visible behavior

### Opening and viewing

- Recognize `.parquet` and compound names ending in `.parquet`, including `.snappy.parquet`. Validate
  with the reader; an extension alone is not proof of a valid file. Additional extension aliases are
  outside v1 unless a real sample establishes the need.
- Open into the existing document workspace and preserve duplicate-open handling. Display a loading
  state while schema and the first page are fetched. Do not create a text editor for this document.
- Show column names and types in the header or header tooltip. Follow existing theme, focus, and
  accessibility conventions rather than copying Dat's full interface.
- Show an explicit empty state for a zero-row file and a different state for zero filter matches.
  Keep the schema and filter controls available in both cases.
- Surface corrupt, unsupported, missing, and inaccessible files through the existing error handling.
  Include a retry/reload path where appropriate; do not present failed reads as empty datasets.

### Sorting and paging

- Clicking a supported column header cycles ascending → descending → unsorted. Sorting another
  column replaces the previous sort. Show the current direction visibly and accessibly.
- Sort using the underlying typed values across all matching rows, not formatted strings or just
  the current page. Keep NULL values last in both directions.
- Reset to the first page after a filter or sort change. Pages must not skip or repeat rows for an
  unchanged file and query, including when sort values tie; establish deterministic page boundaries
  in the data layer. With no sort selected, retain the reader's file order for that viewing session.
- Keep navigation disabled while its replacement page is loading. Do not advertise a next page when
  no further matches exist.

### Filters

Use a compact native popover or sheet with **Column → Operator → Value → Apply**, following existing
presentation patterns. Available operators depend on the schema:

| Column type | Operators |
|-------------|-----------|
| String | Equals, contains, starts with, is NULL, is not NULL |
| Integer, decimal, floating point | Equals, not equals, less than, greater than, inclusive range, is NULL, is not NULL |
| Date, time, timestamp | Equals, before, after, inclusive range, is NULL, is not NULL |
| Boolean | Is true, is false, is NULL, is not NULL |
| Nested or unsupported scalar type | No value filters in v1; allow NULL checks where supported |

- String equality is case-sensitive; contains and starts-with are case-insensitive. Treat input
  literally, including `%`, `_`, quotes, and backslashes. Label the behavior clearly.
- Use typed inputs and validate before applying. Reject invalid numbers, invalid dates, and inverted
  ranges with an inline explanation. Preserve the last valid query if validation fails.
- Clearly distinguish NULL checks from blank-string filters. Ordinary comparisons exclude NULL.
- Removing a chip immediately recomputes the view. Clearing all filters preserves the active sort.
- Apply or remove filters through controls; do not add expression text boxes or SQL shortcuts.

### Formatting

Use schema types and logical annotations rather than guessing from the first rows:

- Integers: exact integer text, right-aligned; never pass large integers through `Double`.
- Decimals: preserve declared scale and precision, right-aligned.
- Floating point: a consistent readable representation that retains meaningful precision; handle
  NaN and infinities explicitly.
- Dates and times: unambiguous date/time text. Preserve available timestamp precision and distinguish
  UTC-adjusted timestamps from local timestamps; do not shift local timestamps into another zone.
- Booleans: consistent true/false text.
- Strings: preserve text, including leading zeros; do not infer dates, currencies, or numeric IDs.
- NULL: a distinct muted `NULL` marker, distinguishable from the literal string `NULL`.
- Lists, structs, maps, and other complex values: compact text with a tooltip for the full value.
  Binary values: a descriptive size/type marker. Disable unsupported sort/value-filter actions.

Bound cell width and displayed text length so a large value cannot stall layout. Avoid formatting
every row in the dataset merely to calculate initial column widths. Sample the loaded page instead.

### Counts and asynchronous updates

- Total rows refers to the unfiltered file; matching rows uses exactly the active filter predicates.
  Neither count is limited to the displayed page. Sorting must not change either count.
- Use footer metadata for the total where available. Run exact filtered counts in the background;
  they can require scanning substantial data.
- Show an explicit counting state until an exact result is available. Never show an earlier query's
  count as if it belongs to the new filters. Distinguish count errors from zero matches.
- Associate pages and counts with a query generation. Cancel obsolete work where supported and
  ignore late completions after filter changes, reload, or close.
- Run reads and queries off the main thread, respecting the engine's connection/threading contract.
  Closing a tab must release its tasks, result buffers, and engine resources.

## Existing integration points

Read `AGENTS.md` and use CodeGraph before locating or changing indexed code. Recheck current source
before implementation; the following map reflects the assessment that produced this plan.

| Component | Required change |
|-----------|-----------------|
| `DocumentPayloadLoader` and `WorkspaceDocumentOpener` | Route Parquet into a typed payload/session instead of attempting UTF-8 decoding; retain asynchronous opening and duplicate handling. |
| `Document` and `DocumentContentController` | Represent read-only table content alongside existing text content without forcing binary data into the text model; guard write entry points. |
| `DocumentFileLifecycleController` | Invalidate pending queries and cached pages on external changes; reuse watcher lifecycle and existing missing-file behavior. |
| `ActiveEditorCoordinator` and the workspace content host | Display the appropriate document view; keep editor-only selection, syntax, and navigation behavior conditional on text content. |
| `AppCommandDispatcher`, menu validation, and status UI | Disable unsupported editing/save actions and show the Parquet footer instead of text cursor/syntax information. |
| `DocumentController`, `Document.supportedTypes`, and `Info.plist` | Add Parquet type recognition and Finder/open routing, including document-type registration as a viewer. |
| `OpenDocumentsStore` and session restoration | Reuse existing identity, tabs, recent files, close/reopen, and saved file references; avoid a second document registry. |
| `Package.swift` and `vmini.xcodeproj/project.pbxproj` | Add the pinned dependency to both build paths and register all new application Swift sources. |

Keep Parquet implementation under `vmini/Features/Parquet/`. Separate engine/session and query logic,
value formatting, table UI, and filter UI into small files according to their responsibilities. Use
concrete types and existing project conventions; a general database-viewer framework is unnecessary.

At the query boundary, bind file paths and values as parameters wherever supported. Allow only
schema-derived column identifiers, quote identifiers correctly, and generate operators from a fixed
enum. User values must never become executable SQL fragments. Handle unusual column names, such as
spaces, quotes, Unicode, and SQL keywords.

For external changes, invalidate results and reload the schema before issuing replacement queries.
Retain sort/filter state only when its referenced columns and types remain compatible; otherwise
clear invalid state with a visible explanation. Never combine counts or pages from different file
versions. Preserve the existing text-document lifecycle behavior.

## Implementation sequence

1. **Prove the engine integration.** Complete the spike, document measured tradeoffs, and pin the
   dependency. Add a small real Parquet fixture covering basic scalar types and NULLs.
2. **Add the read-only document path.** Update payload routing, document representation, type
   registration, workspace hosting, save guards, commands, and restore behavior. Confirm text files
   still follow their existing path.
3. **Render and page the table.** Add schema headers, formatting, loading/error/empty states, bounded
   pages, and total-row information. Keep the UI responsive before adding query controls.
4. **Add sorting and filters.** Implement typed query state, the native filter UI, exact matching
   counts, cancellation, and stale-result rejection. Keep page and count predicates identical.
5. **Finish lifecycle and validation.** Cover external changes, close/reopen, theme and accessibility
   behavior, edge-case fixtures, and representative performance checks. Register sources in Xcode
   and run both build paths.

## Validation and acceptance criteria

Use focused tests in the existing test target. Include real engine queries against small fixtures,
not only tests asserting the generated query text:

- Every supported scalar type formats correctly, including NULL versus empty string, large integers,
  decimal scale, timestamp precision/semantics, and leading-zero strings.
- Numeric and date sorting uses typed values; ascending/descending place NULL last. Tied values at
  page boundaries do not cause missing or repeated rows.
- Each filter operator, AND combinations, chip removal, and Clear Filters produce expected rows.
  Literal wildcard characters and unusual identifiers work; invalid input does not change results.
- Counts match the full filtered result across multiple pages; sorting preserves counts. Cover
  zero rows, zero matches, all-NULL columns, and count failures.
- Late page/count completions cannot overwrite newer state. Closing or reloading invalidates work
  and releases resources, including while a query is running.
- Opening through existing entry points, duplicate opens, restored sessions, mixed text/Parquet tabs,
  external changes, and missing files preserve the expected document lifecycle.
- Parquet Save/Save As and document write entry points cannot modify the source. Confirm fixture
  bytes remain unchanged after opening, filtering, sorting, and closing.
- Existing text editing, save, search, and session workflow tests continue to pass.

Manually check the packaged app:

- Keyboard navigation, focus after tab switches, header sorting, filter controls, page controls, and
  VoiceOver labels work in both themes.
- Opening a corrupt file produces an error; an empty file or unmatched filter produces the correct
  empty state. Long text and nested/binary values do not break layout.
- Offline opening works without external tools or downloads.
- Representative large-file queries leave the UI responsive. Capture memory and latency results,
  and verify cancellation and rapid filter changes during an expensive query.

After implementation, run `swift test -c release` and `./scripts/build.sh` to validate the Swift
package and Xcode source/dependency registration. Report actual checks, measured limits, and any
remaining defects. No implementation, build, or performance validation was performed when writing
this plan.

## Completion

Deliver the basic read-only viewer, focused fixtures/tests, and measured dependency/performance
impact. Keep the excluded features out of this release. The principal unresolved risks are the
DuckDB build/app-size cost and global sort/count behavior on the user's real datasets.
