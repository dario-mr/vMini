# Performance checks

## Run locally

Run the Release benchmark suite:

```bash
./scripts/benchmark-performance.sh --output /tmp/vmini-performance.json
```

It builds the test bundle, measures warm editing and full-document highlighting, then measures cold
Markdown/SQL initialization in five fresh test processes. The JSON report and raw logs are written
next to the requested output. Warm edit scenarios use three untimed edits followed by 50 samples.
Timings cover edit-to-highlighted-attributes; they exclude build and process startup. Ordinary
`swift test` skips these benchmarks.

Useful options:

- `--cold-samples N` changes the number of cold runs; use at least five.
- `--build-only` builds the Release test bundle without measuring.
- `--skip-build` reuses an existing Release test bundle.

## Compare two revisions

Run the benchmark at each revision on the same machine and toolchain, saving each JSON report. Both
revisions must have compatible benchmark harnesses and fixtures. Then compare them:

```bash
python3 scripts/compare_performance.py compare \
  --base /tmp/base.json \
  --candidate /tmp/candidate.json \
  --budgets scripts/performance-budgets.json \
  --summary /tmp/comparison.md \
  --report /tmp/comparison.json
```

The comparator checks medians and edit p95 against each scenario's regression allowance and latency
ceiling. It exits nonzero for regressions, missing results, benchmark failures, or incompatible
reports. Read the Markdown summary first, then use the JSON reports and raw logs to inspect details.
Budgets are in `scripts/performance-budgets.json`.

## Pull request check

The `performance-regression` job in the `Performance regression test` workflow compares the PR base and head on the
same hosted runner. It builds both revisions, alternates their measurement order across three
batches, and uploads reports and logs even when a run fails. For the first PR that adds the harness,
the workflow overlays it onto the base revision so both revisions can be measured. Fixtures are
replaced exactly, including deletions. Production sources in the base checkout are not changed.
Every batch must include every required scenario; a later batch cannot fill in missing results.

The comparator's ordinary unit tests run in the performance workflow. Run them locally:

```bash
python3 -B -m unittest discover -s scripts -p 'test_compare_performance.py' -v
```

## Investigate a slow interaction

For an Instruments trace, run:

```bash
CONFIGURATION=Release ./scripts/profile-interactions.sh
```

While it records, edit a Markdown document with SQL and switch between corpus tabs. Open the saved
trace in Instruments and inspect the signposts for highlighting, parsing, Markdown fence work, and
attribute application.

The benchmark gate covers highlighting latency. It does not measure screen rendering or protect
file-open/tab-switch latency and memory growth.
