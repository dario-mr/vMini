#!/usr/bin/env python3
"""Collect benchmark logs and compare compatible Release reports."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import statistics
import subprocess
import sys
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
RESULT_PREFIX = "VMINI_PERF_RESULT:"
FAILURE_PREFIX = "VMINI_PERF_FAILURE:"
HARNESS_FILES = (
    "Tests/vminiTests/EditorEditingPerformanceTests.swift",
    "Tests/vminiTests/JavaHighlightingPerformanceTests.swift",
    "Tests/vminiTests/PerformanceBenchmark.swift",
    "Tests/vminiTests/SyntaxHighlightingPerformanceTests.swift",
    "scripts/benchmark-performance.sh",
    "scripts/compare_performance.py",
    "scripts/performance-budgets.json",
)
COMPATIBILITY_FIELDS = (
    "buildConfiguration",
    "os",
    "architecture",
    "xcodeVersion",
    "swiftVersion",
    "pythonVersion",
    "runnerName",
    "runnerOS",
    "processorCount",
    "harnessIdentity",
    "corpusIdentity",
    "cpuBrand",
)


def output_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def command_output(command: list[str]) -> str | None:
    try:
        result = subprocess.run(command, check=True, text=True, capture_output=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    return result.stdout.strip()


def digest_files(root: Path, paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda item: item.as_posix()):
        relative = path.relative_to(root).as_posix()
        digest.update(relative.encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def metadata(root: Path, revision: str, configuration: str) -> dict[str, Any]:
    harness_files = [root / name for name in HARNESS_FILES]
    corpus_root = root / "Tests/vminiTests/PerformanceCorpus"
    corpus_files = list(corpus_root.rglob("*")) if corpus_root.exists() else []
    corpus_files = [path for path in corpus_files if path.is_file()]
    xcode = command_output(["xcodebuild", "-version"])
    return {
        "commitSHA": revision,
        "worktreeDirty": bool(command_output(["git", "status", "--porcelain", "--untracked-files=all"]) or ""),
        "buildConfiguration": configuration,
        "os": platform.platform(),
        "architecture": platform.machine(),
        "xcodeVersion": xcode,
        "swiftVersion": command_output(["swift", "--version"]),
        "pythonVersion": platform.python_version(),
        "runnerName": os.environ.get("RUNNER_NAME"),
        "runnerOS": os.environ.get("RUNNER_OS"),
        "cpuBrand": command_output(["sysctl", "-n", "machdep.cpu.brand_string"]) or platform.processor() or None,
        "processorCount": os.cpu_count(),
        "harnessIdentity": digest_files(root, [path for path in harness_files if path.is_file()]),
        "corpusIdentity": digest_files(root, corpus_files),
    }


def nearest_rank_p95(samples: list[float]) -> float:
    return sorted(samples)[math.ceil(len(samples) * 0.95) - 1]


def validate_result(result: Any, require_summary: bool = False) -> list[str]:
    if not isinstance(result, dict):
        return ["result entry is not an object"]
    errors: list[str] = []
    for field in ("scenarioID", "classification", "measurementBoundary", "unit"):
        if not isinstance(result.get(field), str) or not result[field]:
            errors.append(f"result has invalid {field}")
    if isinstance(result.get("inputUTF16Length"), bool) or not isinstance(result.get("inputUTF16Length"), int) or result["inputUTF16Length"] < 0:
        errors.append(f"{result.get('scenarioID', '<unknown>')}: invalid inputUTF16Length")
    samples = result.get("samplesMilliseconds")
    if not isinstance(samples, list) or not samples:
        errors.append(f"{result.get('scenarioID', '<unknown>')}: missing raw samples")
    elif any(isinstance(sample, bool) or not isinstance(sample, (int, float)) or not math.isfinite(sample) or sample < 0 for sample in samples):
        errors.append(f"{result.get('scenarioID', '<unknown>')}: samples must be finite non-negative numbers")
    if result.get("status", "passed") != "passed":
        errors.append(f"{result.get('scenarioID', '<unknown>')}: result status is not passed")
    if require_summary and isinstance(samples, list) and samples and not errors:
        if isinstance(result.get("sampleCount"), bool) or result.get("sampleCount") != len(samples):
            errors.append(f"{result['scenarioID']}: sampleCount does not match raw samples")
        median = result.get("medianMilliseconds")
        if isinstance(median, bool) or not isinstance(median, (int, float)) or not math.isclose(median, statistics.median(samples), rel_tol=1e-9, abs_tol=1e-9):
            errors.append(f"{result['scenarioID']}: median does not match raw samples")
        if result["classification"] == "warm-edit":
            p95 = result.get("p95Milliseconds")
            if isinstance(p95, bool) or not isinstance(p95, (int, float)) or not math.isclose(p95, nearest_rank_p95(samples), rel_tol=1e-9, abs_tol=1e-9):
                errors.append(f"{result['scenarioID']}: p95 does not match raw samples")
        elif "p95Milliseconds" in result:
            errors.append(f"{result['scenarioID']}: p95 is not reported for this classification")
    return errors


def collect(args: argparse.Namespace) -> int:
    root = args.source_root.resolve()
    results: dict[str, dict[str, Any]] = {}
    failures: list[dict[str, Any]] = []
    errors: list[str] = []

    for log_path in args.logs:
        if not log_path.is_file():
            errors.append(f"missing benchmark log: {log_path}")
            continue
        found_ids: set[str] = set()
        found_events = 0
        for line_number, line in enumerate(log_path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            prefix = RESULT_PREFIX if RESULT_PREFIX in line else FAILURE_PREFIX if FAILURE_PREFIX in line else None
            if prefix is None:
                continue
            try:
                event = json.loads(line.split(prefix, 1)[1])
            except (json.JSONDecodeError, IndexError) as error:
                errors.append(f"{log_path}:{line_number}: invalid result JSON: {error}")
                continue
            if prefix == FAILURE_PREFIX:
                if not isinstance(event, dict):
                    errors.append(f"{log_path.name}:{line_number}: failure record is not an object")
                    continue
                failures.append({**event, "source": log_path.name})
                continue

            found_events += 1
            event_errors = validate_result(event)
            errors.extend(f"{log_path.name}: {error}" for error in event_errors)
            if event_errors:
                continue
            scenario_id = event.get("scenarioID")
            if scenario_id in found_ids:
                errors.append(f"{log_path.name}: duplicate scenario ID {scenario_id}")
                continue
            if not isinstance(scenario_id, str):
                continue
            found_ids.add(scenario_id)
            event_samples = event.get("samplesMilliseconds")
            event_samples = list(event_samples) if isinstance(event_samples, list) else []
            prior = results.get(scenario_id)
            if prior is None:
                prior = dict(event)
                prior["samplesMilliseconds"] = event_samples
                results[scenario_id] = prior
            else:
                for field in ("classification", "measurementBoundary", "unit", "inputUTF16Length"):
                    if prior.get(field) != event.get(field):
                        errors.append(f"{scenario_id}: incompatible {field} across benchmark processes")
                prior["samplesMilliseconds"].extend(event_samples)
        if found_events == 0 and not any(failure.get("source") == log_path.name for failure in failures):
            errors.append(f"{log_path.name}: no benchmark results emitted")

    if os.environ.get("VMINI_PERF_TEST_FAILED") == "1":
        errors.append("one or more XCTest benchmark processes failed")

    for result in results.values():
        samples = result["samplesMilliseconds"]
        result["status"] = "passed" if samples and not any(
            isinstance(sample, bool) or not isinstance(sample, (int, float)) or not math.isfinite(sample) or sample < 0
            for sample in samples
        ) else "failed"
        result["sampleCount"] = len(samples)
        if result["status"] == "failed":
            continue
        result["medianMilliseconds"] = statistics.median(samples)
        result.pop("includeP95", None)
        if result["classification"] == "warm-edit":
            if len(samples) < 50:
                errors.append(f"{result['scenarioID']}: warm edit needs at least 50 samples, got {len(samples)}")
            result["p95Milliseconds"] = nearest_rank_p95(samples)
        elif result["classification"] == "cold-initialization" and len(samples) < 5:
            errors.append(f"{result['scenarioID']}: cold initialization needs at least 5 process samples, got {len(samples)}")

    report = {
        "schemaVersion": SCHEMA_VERSION,
        "metadata": metadata(root, args.revision, args.build_configuration),
        "measurementNote": "Edit timings end when expected NSTextStorage attributes are applied; they do not measure screen presentation or input-to-photon latency.",
        "status": "passed" if not errors and not failures else "failed",
        "errors": errors,
        "failures": failures,
        "results": sorted(results.values(), key=lambda result: result["scenarioID"]),
    }
    output_json(args.output, report)
    print(f"Wrote {args.output} ({len(results)} scenarios, {len(failures)} failures, {len(errors)} errors)")
    for result in report["results"]:
        if "medianMilliseconds" not in result:
            print(f"{result['scenarioID']}: no valid samples")
            continue
        line = f"{result['scenarioID']}: n={result['sampleCount']} median={result['medianMilliseconds']:.3f} ms"
        if "p95Milliseconds" in result:
            line += f" p95={result['p95Milliseconds']:.3f} ms"
        print(line)
    return 1 if errors or failures else 0


def validate_report(report: Any, label: str) -> list[str]:
    if not isinstance(report, dict) or report.get("schemaVersion") != SCHEMA_VERSION:
        return [f"{label}: unsupported report schema"]
    errors: list[str] = []
    if report.get("status") != "passed":
        errors.append(f"{label}: report status is not passed")
    if not isinstance(report.get("metadata"), dict):
        errors.append(f"{label}: missing metadata")
    else:
        for field in ("commitSHA", "buildConfiguration", "os", "architecture", "xcodeVersion", "swiftVersion", "pythonVersion", "runnerName", "runnerOS", "processorCount", "worktreeDirty", "harnessIdentity", "corpusIdentity"):
            if field not in report["metadata"]:
                errors.append(f"{label}: metadata is missing {field}")
        if not isinstance(report["metadata"].get("worktreeDirty"), bool):
            errors.append(f"{label}: metadata worktreeDirty must be boolean")
    for field in ("errors", "failures", "results"):
        if not isinstance(report.get(field), list):
            errors.append(f"{label}: {field} must be an array")
    seen: set[str] = set()
    results = report.get("results")
    for result in results if isinstance(results, list) else []:
        errors.extend(f"{label}: {error}" for error in validate_result(result, require_summary=True))
        scenario_id = result.get("scenarioID") if isinstance(result, dict) else None
        if isinstance(scenario_id, str):
            if scenario_id in seen:
                errors.append(f"{label}: duplicate scenario ID {scenario_id}")
            seen.add(scenario_id)
            samples = result.get("samplesMilliseconds", [])
            if result.get("classification") == "warm-edit" and isinstance(samples, list) and len(samples) < 50:
                errors.append(f"{label}:{scenario_id}: needs at least 50 warm edit samples")
            if result.get("classification") == "cold-initialization" and isinstance(samples, list) and len(samples) < 5:
                errors.append(f"{label}:{scenario_id}: needs at least 5 cold process samples")
    if report.get("errors"):
        errors.extend(f"{label}: benchmark error: {error}" for error in report["errors"])
    if report.get("failures"):
        errors.extend(f"{label}: benchmark failure: {failure}" for failure in report["failures"])
    return errors


def compare_reports(
    base_reports: list[dict[str, Any]],
    candidate_reports: list[dict[str, Any]],
    budgets: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[str]]:
    errors: list[str] = []
    for label, reports in (("base", base_reports), ("candidate", candidate_reports)):
        if not reports:
            errors.append(f"{label}: no report supplied")
        for index, report in enumerate(reports):
            errors.extend(validate_report(report, f"{label}[{index}]"))

    base_metadata = base_reports[0].get("metadata") if base_reports and isinstance(base_reports[0], dict) else None
    candidate_metadata = candidate_reports[0].get("metadata") if candidate_reports and isinstance(candidate_reports[0], dict) else None
    base_metadata = base_metadata if isinstance(base_metadata, dict) else {}
    candidate_metadata = candidate_metadata if isinstance(candidate_metadata, dict) else {}
    for field in COMPATIBILITY_FIELDS:
        if base_metadata.get(field) != candidate_metadata.get(field):
            errors.append(f"incompatible {field}: base={base_metadata.get(field)!r}, candidate={candidate_metadata.get(field)!r}")
    for label, reports, reference in (("base", base_reports, base_metadata), ("candidate", candidate_reports, candidate_metadata)):
        for report in reports[1:]:
            if not isinstance(report, dict):
                continue
            meta = report.get("metadata")
            if not isinstance(meta, dict):
                continue
            for field in (*COMPATIBILITY_FIELDS, "commitSHA"):
                if reference.get(field) != meta.get(field):
                    errors.append(f"{label}: batch reports disagree on {field}")

    def gather(reports: list[dict[str, Any]], label: str) -> tuple[dict[str, dict[str, Any]], list[str]]:
        gathered: dict[str, dict[str, Any]] = {}
        local_errors: list[str] = []
        for report in reports:
            if not isinstance(report, dict):
                continue
            seen: set[str] = set()
            results = report.get("results")
            for result in results if isinstance(results, list) else []:
                if validate_result(result):
                    continue
                scenario_id = result["scenarioID"]
                if scenario_id in seen:
                    local_errors.append(f"{label}: duplicate scenario ID {scenario_id}")
                    continue
                seen.add(scenario_id)
                if scenario_id not in gathered:
                    gathered[scenario_id] = dict(result)
                    gathered[scenario_id]["samplesMilliseconds"] = list(result["samplesMilliseconds"])
                else:
                    prior = gathered[scenario_id]
                    for field in ("classification", "measurementBoundary", "unit", "inputUTF16Length"):
                        if prior.get(field) != result.get(field):
                            local_errors.append(f"{label}:{scenario_id}: incompatible {field}")
                    prior["samplesMilliseconds"].extend(result["samplesMilliseconds"])
        return gathered, local_errors

    base, base_errors = gather(base_reports, "base")
    candidate, candidate_errors = gather(candidate_reports, "candidate")
    errors.extend(base_errors + candidate_errors)
    scenario_classes = budgets.get("scenarios", {})
    classes = budgets.get("classes")
    if not isinstance(classes, dict):
        errors.append("budget file has no class definitions")
        classes = {}
    scenarios = {
        scenario_id: classes.get(class_name, {})
        for scenario_id, class_name in scenario_classes.items()
    } if isinstance(scenario_classes, dict) else {}
    if not isinstance(scenarios, dict) or not scenarios:
        errors.append("budget file has no scenarios")
        scenarios = {}
    for label, reports in (("base", base_reports), ("candidate", candidate_reports)):
        for index, report in enumerate(reports):
            results = report.get("results") if isinstance(report, dict) else None
            actual = {
                result["scenarioID"] for result in results if not validate_result(result)
            } if isinstance(results, list) else set()
            for scenario_id in scenarios.keys() - actual:
                errors.append(f"missing required {label} scenario: {scenario_id} in batch {index + 1}")
            for scenario_id in actual - scenarios.keys():
                errors.append(f"unbudgeted {label} scenario: {scenario_id} in batch {index + 1}")

    rows: list[dict[str, Any]] = []
    for scenario_id, budget in scenarios.items():
        if scenario_id not in base or scenario_id not in candidate:
            continue
        before = base[scenario_id]
        after = candidate[scenario_id]
        if not isinstance(budget, dict) or not isinstance(budget.get("metrics"), dict):
            errors.append(f"{scenario_id}: invalid scenario budget")
            continue
        metric_budgets = budget["metrics"]
        if before.get("classification") != after.get("classification") or before.get("classification") != budget.get("classification"):
            errors.append(f"{scenario_id}: classification mismatch")
            continue
        if before.get("measurementBoundary") != after.get("measurementBoundary"):
            errors.append(f"{scenario_id}: measurement boundary mismatch")
            continue
        if before.get("unit") != after.get("unit") or before.get("inputUTF16Length") != after.get("inputUTF16Length"):
            errors.append(f"{scenario_id}: unit or input length mismatch")
            continue
        before_samples = before["samplesMilliseconds"]
        after_samples = after["samplesMilliseconds"]
        metrics: dict[str, tuple[float, float]] = {
            "medianMilliseconds": (statistics.median(before_samples), statistics.median(after_samples)),
        }
        if "p95Milliseconds" in metric_budgets:
            if len(before_samples) < 20 or len(after_samples) < 20:
                errors.append(f"{scenario_id}: p95 comparison needs at least 20 samples per revision")
                continue
            metrics["p95Milliseconds"] = (nearest_rank_p95(before_samples), nearest_rank_p95(after_samples))
        elif before.get("classification") == "warm-edit":
            errors.append(f"{scenario_id}: warm edit budget must compare p95 separately")
            continue
        for metric_name, (base_value, candidate_value) in metrics.items():
            metric_budget = metric_budgets.get(metric_name)
            if not isinstance(metric_budget, dict):
                errors.append(f"{scenario_id}: missing budget for {metric_name}")
                continue
            relative = metric_budget.get("relativeAllowance")
            absolute = metric_budget.get("absoluteAllowanceMilliseconds")
            ceiling = metric_budget.get("ceilingMilliseconds")
            if any(isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0 for value in (relative, absolute, ceiling)):
                errors.append(f"{scenario_id}: invalid {metric_name} budget")
                continue
            delta = candidate_value - base_value
            reasons = []
            if candidate_value > ceiling:
                reasons.append(f"candidate exceeds {ceiling:g} ms ceiling")
            if delta > absolute and candidate_value > base_value * (1 + relative):
                reasons.append(f"increase exceeds {relative:.0%} and {absolute:g} ms allowances")
            rows.append({
                "scenarioID": scenario_id,
                "metric": metric_name,
                "baseMilliseconds": base_value,
                "candidateMilliseconds": candidate_value,
                "deltaMilliseconds": delta,
                "relativeAllowance": relative,
                "absoluteAllowanceMilliseconds": absolute,
                "ceilingMilliseconds": ceiling,
                "status": "failed" if reasons else "passed",
                "reasons": reasons,
            })
    return rows, errors


def markdown_summary(rows: list[dict[str, Any]], errors: list[str], base_sha: str | None = None, candidate_sha: str | None = None) -> str:
    lines = ["## Performance regression comparison", ""]
    if base_sha or candidate_sha:
        lines.extend([f"Base commit: `{base_sha or 'missing'}`  ", f"Candidate commit: `{candidate_sha or 'missing'}`", ""])
    lines.extend(["| Scenario | Metric | Base (ms) | Candidate (ms) | Delta (ms) | Budget | Result | Reason |", "|---|---:|---:|---:|---:|---|---|---|"])
    for row in rows:
        budget = f"+{row['absoluteAllowanceMilliseconds']:g} ms and {row['relativeAllowance']:.0%}; ceiling {row['ceilingMilliseconds']:g} ms"
        metric = {"medianMilliseconds": "Median", "p95Milliseconds": "P95"}.get(row["metric"], row["metric"])
        result = "❌" if row["status"] == "failed" else "✅"
        lines.append(
            f"| `{row['scenarioID']}` | {metric} | {row['baseMilliseconds']:.3f} | {row['candidateMilliseconds']:.3f} | {row['deltaMilliseconds']:+.3f} | {budget} | {result} | {'; '.join(row['reasons']) or '—'} |"
        )
    if errors:
        lines.extend(["", "### Comparison errors", ""])
        lines.extend(f"- {error}" for error in errors)
    return "\n".join(lines) + "\n"


def run_compare(args: argparse.Namespace) -> int:
    try:
        budgets = json.loads(args.budgets.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"Cannot read budgets: {error}", file=sys.stderr)
        return 2
    base_reports: list[dict[str, Any]] = []
    candidate_reports: list[dict[str, Any]] = []
    input_errors: list[str] = []
    for label, paths, target in (("base", args.base, base_reports), ("candidate", args.candidate, candidate_reports)):
        for path in paths:
            try:
                target.append(json.loads(path.read_text(encoding="utf-8")))
            except (OSError, json.JSONDecodeError) as error:
                input_errors.append(f"{label}: cannot read {path}: {error}")
    if not isinstance(budgets, dict) or budgets.get("schemaVersion") != SCHEMA_VERSION:
        print("Unsupported budget schema", file=sys.stderr)
        return 2
    rows, errors = compare_reports(base_reports, candidate_reports, budgets)
    errors = input_errors + errors
    base_metadata = base_reports[0].get("metadata") if base_reports and isinstance(base_reports[0], dict) else None
    candidate_metadata = candidate_reports[0].get("metadata") if candidate_reports and isinstance(candidate_reports[0], dict) else None
    base_sha = base_metadata.get("commitSHA") if isinstance(base_metadata, dict) else None
    candidate_sha = candidate_metadata.get("commitSHA") if isinstance(candidate_metadata, dict) else None
    summary = markdown_summary(rows, errors, base_sha, candidate_sha)
    if args.summary:
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        args.summary.write_text(summary, encoding="utf-8")
    print(summary, end="")
    failures = [row for row in rows if row["status"] == "failed"]
    categories: set[str] = set()
    if failures:
        categories.add("regression")
    for error in errors:
        lowered = error.lower()
        if "missing required" in lowered or "missing base scenario" in lowered or "missing candidate scenario" in lowered or "no report supplied" in lowered or "unbudgeted" in lowered:
            categories.add("missing-scenario")
        if "incompatible" in lowered or "mismatch" in lowered or "disagree" in lowered:
            categories.add("incompatible-comparison")
        if "benchmark error" in lowered or "no benchmark results" in lowered or "xctest benchmark processes failed" in lowered or "missing benchmark log" in lowered or "report status is not passed" in lowered:
            categories.add("benchmark-error")
        if "samples" in lowered or "p95 comparison" in lowered or "invalid" in lowered or "does not match raw samples" in lowered or "budget file" in lowered:
            categories.add("invalid-report")
    if any(isinstance(report, dict) and report.get("failures") for report in base_reports + candidate_reports):
        categories.add("correctness-failure")
    result = {
        "schemaVersion": SCHEMA_VERSION,
        "status": "failed" if errors or failures else "passed",
        "baseCommitSHA": base_sha,
        "candidateCommitSHA": candidate_sha,
        "failureCategories": sorted(categories),
        "errors": errors,
        "regressions": failures,
        "comparisons": rows,
    }
    if args.report:
        output_json(args.report, result)
    return 1 if errors or failures else 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)
    collect_parser = commands.add_parser("collect", help="convert XCTest log lines to versioned JSON")
    collect_parser.add_argument("--source-root", type=Path, required=True)
    collect_parser.add_argument("--revision", required=True)
    collect_parser.add_argument("--build-configuration", default="Release")
    collect_parser.add_argument("--output", type=Path, required=True)
    collect_parser.add_argument("--logs", type=Path, nargs="+", required=True)
    collect_parser.set_defaults(run=collect)

    compare_parser = commands.add_parser("compare", help="compare base and candidate JSON reports")
    compare_parser.add_argument("--base", type=Path, action="append", required=True)
    compare_parser.add_argument("--candidate", type=Path, action="append", required=True)
    compare_parser.add_argument("--budgets", type=Path, required=True)
    compare_parser.add_argument("--summary", type=Path)
    compare_parser.add_argument("--report", type=Path)
    compare_parser.set_defaults(run=run_compare)
    return root


if __name__ == "__main__":
    args = parser().parse_args()
    raise SystemExit(args.run(args))
