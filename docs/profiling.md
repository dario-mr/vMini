# Performance profiling

## Interaction profile

On macOS with Xcode and Instruments installed, record app activity for 45 seconds with a Release
build:

```bash
CONFIGURATION=Release ./scripts/profile-interactions.sh
```

The script builds the app, launches it under `xctrace`, and records `Time Profiler` and the app's
signpost intervals. Add `--duration 30s` to change the duration. While recording, open
`Tests/vminiTests/PerformanceCorpus` in the folder sidebar, expand `ChangingTree`, open the large
Markdown, JSON, and Bash files, edit a Markdown paragraph, change a file in the corpus folder, then
switch tabs and bring vMini back to the foreground.

Use `--skip-build` to reuse the current build, or `--attach-pid <pid>` to profile an already-running
process. The latter also skips launching a new app instance. The script saves a timestamped folder
under `profiles/` containing `vmini.trace`, `trace-toc.xml`, and `run-info.txt`. Open the trace in
Instruments with `open path/to/vmini.trace`.

## Syntax highlighting benchmark

Run the Release benchmark manually:

```bash
./scripts/benchmark-performance.sh
```

It measures the token-dense JSON, multiline Bash, and large Markdown corpora after one warm-up, with
five timed samples per corpus. It prints each median and sample timings; the test checks that
highlighting preserves the input's UTF-16 length.

The benchmark test is discovered by regular `swift test` runs, but skips measurement unless
`VMINI_RUN_PERFORMANCE_BENCHMARK=1` is set. The script sets that flag and filters to the benchmark
test while building and running tests in Release.
