# DuckDB integration spike

Implemented on 2026-11-05. This covers the integration spike, not document routing or the table UI.

**Shipping-size follow-up:** a stripped, coverage-free universal archive adds **51.95 MiB** to the
app and **17.79 MiB** to the ZIP download. The earlier 250.04 MiB increase described an unstripped,
coverage-instrumented development build, not the shipping footprint. See the archive comparison below.

## Decision

The official package can read Parquet offline inside the app on both supported architectures.
Pin `duckdb-swift` **1.1.3**, revision `9583f44fedc20a8e0b6151d2e43f6d850016712f`, in both
build paths. This was the latest stable tag available in the official package repository during
the spike, rather than a development snapshot.

The public Swift `Connection` has **no interruption API**, including on the checked upstream main
branch. `ParquetConnection` (originally `DuckDBSpikeConnection`) therefore owns the C database/connection handles from the same
package's `Cduckdb` module. It serializes queries, allows interruption from another thread, binds
file paths and filter values, and destroys statements, results, connections, and databases.
No reflection, private Swift handles, external DuckDB executable, or downloaded extension is used.
The public Swift API is also exercised by fixture generation. Both build systems verify that the
transitive C module is available at this pin.

Proceed with the C-backed connection approach for a viewer session. An implementation confined to
the current high-level Swift wrapper cannot meet the cancellation requirement. The app-size cost
below remains a significant product tradeoff; this spike does not optimize or fork the dependency.

## State after spike cleanup

The decision is to continue with DuckDB. The pinned package, C-backed `ParquetConnection`, small
real Parquet fixture, and five integration tests are retained. The connection remains the starting
point for typed results, query/session lifecycle, and the read-only document path in the next steps.

The application no longer contains a benchmark runner, fixture generator, or `--parquet-spike*`
launch modes. `VminiApp` uses its normal startup path. Codec fixture generation lives only in
`Tests/vminiTests/Features/Parquet/ParquetTestFixtures.swift`; cancellation and resource checks live
in `ParquetIntegrationTests.swift`. The 5-million-row generator and diagnostic query/printing code
were removed. Both SwiftPM and Xcode register the production/test sources in their proper targets.

Run the retained engine checks and normal app build from the repository root:

```sh
swift test -c release --filter ParquetIntegrationTests
CONFIGURATION=Release ./scripts/build.sh
```

The original packaged offline and performance probes were completed before this cleanup. Their
results below are historical measurements of that build; the old launch modes are no longer
available. Recheck the shipping footprint and packaged behavior when the viewer is wired into the
app. The shipping archive recipe below still applies to the build configuration.

Removed **13.21 GiB** of generated artifact allocations (as reported by `du`): throwaway
Xcode build directories, the copied baseline source, archives, ZIPs, generated datasets, and the
duplicate `.build/xcode-packages` cache. Small logs/JSON/section inspections remain under
`profiles/parquet-spike/` and `profiles/parquet-shipping-size/` (about 17 MiB combined). The cleanup
manifest is `profiles/parquet-cleanup.json`. The committed 1,357-byte fixture and the supplied files
in Downloads were preserved; ordinary SwiftPM and Xcode development caches were left in place.

Cleanup validation: the normal Release app build and universal Xcode `build-for-testing` passed.
`swift test -c release --jobs 6` passed with 294 tests, 6 existing skips, and zero failures after
compilation finished. An initial run during concurrent Xcode compilation hit the workspace test
`testSelectingAnAlreadyOpenTabInvalidatesPendingOpenSelection`'s short wait; it passed in the
subsequent full-suite run without changing workspace code. Size benchmarks and Rosetta execution
were not repeated as part of cleanup.

## Environment and build impact

Apple M2 Pro, 12 CPU cores, 32 GB RAM; macOS 26.6.2; Xcode 27.2 (27B52), SDK 27.2.
App Release configuration, macOS deployment target **13.0**, universal **arm64 + x86_64**.
The dependency is built from source, with bundled Parquet, ICU, and JSON extensions. Mach-O build
commands record minimum macOS 13.0 for both app slices; running on macOS 13 itself was not available.

### Initial development-build measurement

| Measurement | Before DuckDB | With DuckDB |
| --- | ---: | ---: |
| Fresh-derived-data universal Release build | 62.50 s | 457.47 s |
| Release app, sum of file sizes | 70,497,301 bytes (67.23 MiB) | 332,680,917 bytes (317.27 MiB) |

App-size increase: **262,183,616 bytes (250.04 MiB)**. These are the project's current unstripped
Release builds; the package compiler invocations also contain `-fprofile-instr-generate` and
`-fcoverage-mapping`. These are not stripped archive or compressed download sizes. No release
settings were changed to reduce the measured cost.

The baseline is commit `b37ec87b38d94a70cdd3a9e3b7d50c4476eac5bc`.
Build times are single observations with source-package caches available, not repeated controlled
benchmarks. The integrated build used `-jobs 6`; the baseline used Xcode's default parallelism, and
some integration compilation overlapped Swift package validation. Treat the times as the observed
cost on this workstation, not a precise regression ratio. The initial incremental Swift Release
build after adding the dependency took 202.37 s; that was not a clean build.

### Shipping archive measurement

Measured later on the same workstation and toolchain using actual Release **archive** actions for
both the baseline commit and the spike working tree before cleanup. Both apps contain **arm64 + x86_64**.
Coverage instrumentation was disabled, dead-code stripping was enabled, and Xcode performed its
normal executable stripping step. Both archived apps were then ad-hoc signed and compressed with
the same `ditto -c -k --keepParent` command used by `scripts/package.sh`.

| Shipping artifact | Before DuckDB | With DuckDB | Increase |
| --- | ---: | ---: | ---: |
| App bundle | 25.72 MiB | 77.67 MiB | **51.95 MiB** |
| ZIP download | 4.52 MiB | 22.31 MiB | **17.79 MiB** |

Exact app sizes: **26,971,765 → 81,445,989 bytes**; increase **54,474,224 bytes**.
Exact ZIP sizes: **4,741,692 → 23,392,278 bytes**; increase **18,650,586 bytes**.
App size is the sum of regular-file sizes in the `.app`, including resources and its local signature.
Archive dSYMs, source checkouts, test bundles, generated datasets, and build intermediates are excluded
from the shipping artifacts. This historical comparison retained all spike code at measurement time; no DuckDB extensions
were removed, and no dependency fork or architecture reduction was used.

The baseline source was extracted from commit `b37ec87b38d94a70cdd3a9e3b7d50c4476eac5bc`
into `profiles/parquet-shipping-size/baseline-source/`. The integrated archive command was:

```sh
xcodebuild -project vmini.xcodeproj -scheme vMini -configuration Release \
  -derivedDataPath profiles/parquet-shipping-size/integrated-derived \
  -clonedSourcePackagesDirPath .build/xcode-packages \
  -archivePath profiles/parquet-shipping-size/integrated.xcarchive \
  ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' CODE_SIGNING_ALLOWED=NO \
  CLANG_ENABLE_CODE_COVERAGE=NO GCC_GENERATE_TEST_COVERAGE_FILES=NO \
  GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO DEAD_CODE_STRIPPING=YES \
  ENABLE_TESTABILITY=NO -jobs 6 archive

measured_app="$PWD/profiles/parquet-shipping-size/integrated.xcarchive/Products/Applications/vMini.app"
codesign --force --sign - "$measured_app"
ditto -c -k --keepParent "$measured_app" profiles/parquet-shipping-size/integrated.zip
```

The baseline used identical options with its own project, derived-data directory, and archive path.
Validation confirmed coverage flags are absent from both DuckDB architecture compiler configurations,
both final app slices have no `__LLVM_COV`, `__llvm_prf*`, or `__DWARF` sections, and the app signatures
pass `codesign --verify --deep --strict`. The stripped integrated app passed the complete offline
Parquet/codec, cancellation, and resource-limit probe on native arm64. The Intel slice was checked
structurally; Rosetta was not launched again for this measurement.

The measurement JSON, section inspection, build logs, and offline smoke-test log are
retained under ignored `profiles/parquet-shipping-size/`; the generated ZIPs and archives were removed during cleanup. **No release script or project setting was changed**;
the smaller result requires the coverage-off settings used here. Developer ID signing, notarization,
and exported-package sizes were not measured. The local ad-hoc signatures are included in both sizes.

## Files and query measurements

The probe discovers schema and converts only a SQL-bounded page of up to 1,000 rows. It obtains an
exact unfiltered count, runs a bound typed filter over the whole file, obtains its exact count, and
sorts matching rows by the same schema-derived column with NULLs last. Numeric columns use an
`Int64(3)` lower bound; a string-only schema uses a bound empty-string lower bound. Identifier
quotes are escaped. This probe has one page; deterministic multipage tie handling belongs to the
viewer implementation.

The committed real Parquet fixture has 6 rows, 9 columns, and Snappy compression (1,357 bytes).
It includes BIGINT values above Double's exact range, DECIMAL(20,4), DOUBLE, BOOLEAN, DATE, TIME,
TIMESTAMP, quoted/Unicode identifiers, NULL, empty text, and leading-zero text. Its SHA-256 is
`9ea64c26b7a1e660b5bead548726775ad28e4640d4bc1d58e4997c115e7dfd6d`.
The retained test fixture generator makes equivalent Gzip, Zstandard, and uncompressed files; all four codecs pass with
automatic installation and loading of extensions disabled. `duckdb_extensions()` reports Parquet
as loaded and `STATICALLY_LINKED`.

Native arm64 results: medians of three separate offline Release app processes; peak RSS is the
maximum of the three runs. The normal build script produced a host-architecture app; the explicit
universal build above was used separately for architecture and Rosetta validation.
These timing/RSS results use the original instrumented Release builds, not the shipping archives
from the follow-up size measurement.

| File | Rows × columns | File bytes / codec | Matches | First page | Total count | Filtered sort + count | Peak RSS |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| `VP_WH.parquet` | 652 × 9 | 9,684 / Zstandard | 652 | 15.2 ms | 1.7 ms | 6.3 ms | 63.6 MiB |
| `promo_export_v2.snappy.parquet` | 1,601,186 × 17 | 14,211,657 / Snappy | 436,285 | 117.2 ms | 78.0 ms | 505.2 ms | 118.5 MiB |
| `large.zstd.parquet` | 5,000,000 × 9 | 105,641,687 / Zstandard (generated) | 4,999,997 | 30.4 ms | 4.7 ms | 2167.8 ms | 125.8 MiB |

The selected filter columns were `PROMOTION_ID`, `priceNorm`, and `id`, respectively.
The generated file has deterministic numeric/date/boolean columns and an MD5 string column; it is
a useful scale check, not a substitute for varied customer datasets. SHA-256 checks before and
after the queries confirm both supplied files are unchanged. The supplied Snappy file stores its
date-like fields as VARCHAR; the future viewer must preserve those schema types.

First-page time means engine initialization, schema discovery, fetching, and converting the page,
not AppKit rendering. Each file probe starts a fresh process/engine; filesystem caches are warm.
Filtered time includes both exact matching count and the bounded sorted page. Count and page use
the same predicate. Total count is separate and can use Parquet metadata. Peak RSS is measured by
`/usr/bin/time -l` for the whole process, including runtime/library overhead; it is not just the
result-page buffer. No cell values from the supplied files are logged.

## Cancellation and resource behavior

Probe configuration: **128 MB DuckDB memory setting, 2 threads, no spill directory**, extension
autoinstall/autoload both disabled. A separate **32 MB** connection runs a high-cardinality
aggregation until DuckDB returns a controlled out-of-memory error. A subsequent `SELECT 42`
succeeds, proving the connection remains usable. The cap is DuckDB's buffer-manager limit, **not
a hard process-RSS cap**; the measured RSS can exceed it. Larger sorts can fail with this deliberate
no-spill policy. A production viewer must decide how to budget all concurrent sessions and whether
to allow bounded temporary spill files.

A long streaming `sum(sin(...))` query runs on a background queue and is interrupted through
`duckdb_interrupt` from another queue. The probe checks the engine's interruption error type,
stops the interrupt timer, and reuses the connection successfully. The timer starts after 100 ms;
the reported `cancel_ms` includes that delay and should not be interpreted as interruption latency
alone. An earlier cross-join probe exhausted the memory budget before interruption and was replaced
so the cancellation and resource checks exercise different behaviors.

Validation completed:

- `swift test -c release --jobs 6`: 294 tests, 6 existing skips, zero failures. Five new real-engine
  tests cover the fixture, exact values, bound values/unusual paths and identifiers, page bounds,
  codecs/public Swift API, missing/corrupt errors, cancellation, and resource failure/reuse.
- `CONFIGURATION=Release ./scripts/build.sh`: passed.
- Xcode `build-for-testing` with `ENABLE_TESTABILITY=YES`: passed for both architectures, including
  the new test source and transitive C module. The first attempt without the override failed
  because the normal Release app module is built without `-enable-testing`; no project setting
  change was needed.
- Explicit universal Release Xcode build: passed; `lipo` confirms arm64 and x86_64, and `vtool`
  confirms minimum macOS 13.0 for both. `otool -L` lists system libraries/frameworks, with no
  dependency on a user-installed DuckDB library.
- Packaged app with network access denied: all four codec reads, schema/page/filter/sort/count,
  cancellation, and controlled memory failure passed on arm64 and x86_64 under Rosetta.
- Native arm64 complete probe: approximately 103 ms including the interrupt timer's 100 ms delay;
  peak RSS 131.1 MiB for the combined codec/large-file/cancellation/resource probe.
- Final Rosetta complete probe: approximately 105 ms for the same cancellation check and
  251.2 MiB peak RSS for the combined probe.
- `git diff --check`: passed. Source sample and fixture immutability checks passed.

Raw build logs, per-run timings/RSS, and checksums are retained under ignored
`profiles/parquet-spike/`. Generated files were removed during cleanup. No personal sample data was committed.

## Acceptance targets and remaining work

For these samples and this workstation, use provisional targets of **under 500 ms** to prepare the
first 1,000 rows, **under 3 s** for the tested filtered sort plus exact count, **under 512 MiB** peak
process RSS per probe, and cancellation completing **within 1 s** including the 100 ms probe delay.
Keep 1,000 rows as the initial page size. These targets are based on the measured files, not a
multi-gigabyte or arbitrary-schema guarantee. Recheck them with the native table and concurrent tabs.

The retained connection's string cell snapshots are not the viewer's final formatting model. Typed
value retention, nanosecond/timezone semantics, nested/binary rendering, all filter operators,
deterministic paging, query generations, close/reload cancellation, session-wide memory budgets,
document read-only guards, accessibility, and the UI remain in subsequent plan steps. No UI latency
or macOS 13 runtime claim is made. User samples were read locally and were not copied into the repo.

## References

- [Official Swift package and pin](https://github.com/duckdb/duckdb-swift/tree/v1.1.3)
- [Pinned Swift connection source](https://github.com/duckdb/duckdb-swift/blob/v1.1.3/Sources/DuckDB/Connection.swift)
- [Pinned package build manifest](https://github.com/duckdb/duckdb-swift/blob/v1.1.3/Package.swift)
- [Pinned C API header](https://github.com/duckdb/duckdb-swift/blob/v1.1.3/Sources/Cduckdb/include/duckdb.h)
- [DuckDB resource limits](https://duckdb.org/docs/current/operations_manual/limits)
