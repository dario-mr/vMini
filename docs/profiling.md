# Performance checks

## Run a local regression check

Compare the current checkout against the merge base with the locally available `origin/main`:

```bash
./scripts/compare-performance-local.sh
```

The candidate includes staged, unstaged, and untracked changes. No branch, commit, or push is
required. The baseline runs in a temporary worktree; the current benchmark harness and fixtures are
overlaid onto it so both revisions use the same measurements. Both Release test bundles are built
before timing, then three alternating base/candidate batches run. Reports, raw logs, build logs, and
the Markdown comparison are saved under `profiles/performance-regression-<timestamp>/`.

The default uses the local `origin/main` ref without fetching. Run `git fetch origin main` first if
you need an up-to-date baseline. Use `--base REF` to compare against an exact commit instead.

## Pull request check

The `performance-regression` job in the `Performance regression test` workflow compares the PR base
and head on the same hosted runner. It builds both revisions, alternates their measurement order
across three batches, and uploads reports and logs even when a run fails. The workflow overlays the
benchmark harness and fixtures onto the base revision so both revisions use the same measurements.
Fixtures are replaced exactly, including deletions. Production sources in the base checkout are not
changed. Benchmark suites live in their feature folders, shared support lives in
`Tests/vminiTests/Support`, and fixtures live in `PerformanceCorpus`.
Every batch must include every required scenario; a later batch cannot fill in missing results.
A scenario fails only when it exceeds its budget both on the pooled samples and in every batch, so
a slow moment on a shared runner that spoils one batch does not fail the check.

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

The gate covers highlighting latency and offscreen drawing of a real editor viewport. It does not
measure screen presentation, input-to-photon latency, file-open/tab-switch latency, or memory growth.
