import math
import argparse
import contextlib
import io
import json
import statistics
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
from compare_performance import HARNESS_FILES, collect, compare_reports, metadata as report_metadata  # noqa: E402


class ComparePerformanceTests(unittest.TestCase):
    metadata = {
        "commitSHA": "abc123",
        "worktreeDirty": False,
        "buildConfiguration": "Release",
        "os": "macOS test",
        "architecture": "arm64",
        "xcodeVersion": "Xcode test",
        "swiftVersion": "Swift test",
        "pythonVersion": "Python test",
        "runnerName": None,
        "runnerOS": None,
        "processorCount": 1,
        "harnessIdentity": "harness-a",
        "corpusIdentity": "corpus-a",
        "cpuBrand": "test CPU",
    }

    def report(self, value, scenario_id="edit.test", classification="warm-edit", samples=None, metadata=None):
        if samples is None:
            samples = [value] * (50 if classification == "warm-edit" else 5)
        return {
            "schemaVersion": 1,
            "metadata": {**self.metadata, **(metadata or {})},
            "status": "passed",
            "errors": [],
            "failures": [],
            "results": [{
                "scenarioID": scenario_id,
                "classification": classification,
                "measurementBoundary": "edit-to-attribute",
                "unit": "milliseconds",
                "inputUTF16Length": 100,
                "samplesMilliseconds": samples,
                "sampleCount": len(samples),
                "medianMilliseconds": statistics.median(samples) if samples else value,
                "p95Milliseconds": value,
                "status": "passed",
            }],
        }

    def budgets(self, relative=0.2, absolute=5, ceiling=100):
        return {
            "classes": {
                "warm-edit": {
                    "classification": "warm-edit",
                    "metrics": {
                        "medianMilliseconds": {
                            "relativeAllowance": relative,
                            "absoluteAllowanceMilliseconds": absolute,
                            "ceilingMilliseconds": ceiling,
                        },
                        "p95Milliseconds": {
                            "relativeAllowance": relative,
                            "absoluteAllowanceMilliseconds": absolute,
                            "ceilingMilliseconds": ceiling,
                        },
                    },
                }
            },
            "scenarios": {"edit.test": "warm-edit"},
        }

    def compare(self, base, candidate, budgets=None):
        return compare_reports([base], [candidate], budgets or self.budgets())

    def test_unchanged_and_faster_results_pass(self):
        for base, candidate in ((10, 10), (10, 8)):
            rows, errors = self.compare(self.report(base), self.report(candidate))
            self.assertEqual(errors, [])
            self.assertTrue(rows)
            self.assertTrue(all(row["status"] == "passed" for row in rows))

    def test_relative_and_absolute_thresholds_are_both_required(self):
        # Relative-only exceedance.
        rows, _ = self.compare(self.report(10), self.report(12.1), self.budgets(relative=0.2, absolute=5))
        self.assertEqual(rows[0]["status"], "passed")
        # Absolute-only exceedance and exact relative boundary.
        rows, _ = self.compare(self.report(10), self.report(11.1), self.budgets(relative=0.2, absolute=1))
        self.assertEqual(rows[0]["status"], "passed")
        rows, _ = self.compare(self.report(10), self.report(12), self.budgets(relative=0.2, absolute=1))
        self.assertEqual(rows[0]["status"], "passed")
        # Both strict thresholds exceeded.
        rows, _ = self.compare(self.report(10), self.report(12.1), self.budgets(relative=0.2, absolute=1))
        self.assertEqual(rows[0]["status"], "failed")

    def test_absolute_ceiling_fails_even_when_base_is_already_slow(self):
        rows, _ = self.compare(self.report(100), self.report(101), self.budgets(relative=0.5, absolute=50, ceiling=100))
        self.assertEqual(rows[0]["status"], "failed")
        self.assertIn("ceiling", rows[0]["reasons"][0])

    def test_zero_baseline_uses_absolute_allowance_without_division(self):
        budgets = self.budgets(relative=0.2, absolute=5)
        rows, _ = self.compare(self.report(0), self.report(5), budgets)
        self.assertEqual(rows[0]["status"], "passed")
        rows, _ = self.compare(self.report(0), self.report(5.1), budgets)
        self.assertEqual(rows[0]["status"], "failed")

    def test_missing_and_duplicate_scenario_ids_fail(self):
        empty = self.report(10)
        empty["results"] = []
        _, errors = self.compare(empty, self.report(10))
        self.assertTrue(any("missing required base scenario" in error for error in errors))

        duplicate = self.report(10)
        duplicate["results"].append(dict(duplicate["results"][0]))
        _, errors = self.compare(duplicate, self.report(10))
        self.assertTrue(any("duplicate scenario ID" in error for error in errors))

    def test_invalid_samples_fail_without_crashing(self):
        for samples in ([], [-1.0] * 50, [math.nan] * 50, [math.inf] * 50):
            _, errors = self.compare(self.report(10, samples=samples), self.report(10))
            self.assertTrue(any("samples" in error for error in errors), samples)

        malformed = self.report(10)
        malformed["results"] = None
        _, errors = self.compare(malformed, self.report(10))
        self.assertTrue(any("results must be an array" in error for error in errors))

    def test_report_summary_must_match_raw_samples(self):
        report = self.report(10)
        report["results"][0]["p95Milliseconds"] = 99
        _, errors = self.compare(report, self.report(10))
        self.assertTrue(any("p95 does not match raw samples" in error for error in errors))

    def test_every_batch_must_include_every_required_scenario(self):
        missing = self.report(10)
        missing["results"] = []
        for base, candidate in (([self.report(10), missing], [self.report(10)]),
                                ([self.report(10)], [missing, self.report(10)])):
            _, errors = compare_reports(base, candidate, self.budgets())
            self.assertTrue(any("missing required" in error and "batch" in error for error in errors))

    def test_collect_malformed_events_writes_failed_report_without_crashing(self):
        for changes in ({"scenarioID": []}, {"classification": None}, {"samplesMilliseconds": ["bad"]}):
            with self.subTest(changes=changes), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                event = {**self.report(10)["results"][0], **changes}
                log = root / "warm.log"
                log.write_text("VMINI_PERF_RESULT:" + json.dumps(event) + "\n")
                args = argparse.Namespace(source_root=root, revision="abc123", build_configuration="Release",
                                          output=root / "report.json", logs=[log])
                with patch("compare_performance.metadata", return_value=self.metadata), contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(collect(args), 1)
                report = json.loads(args.output.read_text())
                self.assertEqual(report["status"], "failed")
                self.assertTrue(report["errors"])

    def test_metadata_uses_github_runner_environment_names(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(
            "os.environ", {"RUNNER_NAME": "runner-test", "RUNNER_OS": "macOS"}
        ), patch("compare_performance.command_output", return_value="test"):
            meta = report_metadata(Path(directory), "abc123", "Release")
            self.assertEqual(meta["runnerName"], "runner-test")
            self.assertEqual(meta["runnerOS"], "macOS")

    def test_harness_fingerprint_paths_exist_after_source_moves(self):
        root = Path(__file__).resolve().parent.parent
        for name in HARNESS_FILES:
            with self.subTest(name=name):
                self.assertTrue((root / name).is_file(), name)

    def test_incompatible_harness_or_corpus_fails(self):
        for field, value in (("harnessIdentity", "harness-b"), ("corpusIdentity", "corpus-b")):
            _, errors = self.compare(
                self.report(10), self.report(10, metadata={field: value})
            )
            self.assertTrue(any(f"incompatible {field}" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
