# OpenIntelligence RAG Benchmarks

This folder contains local benchmark manifests for the existing debug validation
harness. It does not replace the app's RAG pipeline and does not change
retrieval, ranking, generation, or verification behavior.

The runner launches the Debug build with `--rag-validation`, lets
`DebugRAGValidationHarness` ingest/query through `RAGService.queryWithAudit`,
then preserves each case's `rag_validation_report.txt` and `pipeline_trace.log`.

## Manifest Format

Benchmark manifests are JSON files with a top-level `cases` array:

```json
{
  "version": 1,
  "name": "my-local-suite",
  "defaults": {
    "quality_mode": "standard",
    "timeout_seconds": 300
  },
  "cases": [
    {
      "id": "fuel_capacity",
      "category": "exact_value",
      "input_files": ["Benchmarks/Fixtures/private_manual.pdf"],
      "query": "How many gallons of gasoline can this vehicle hold?",
      "quality_mode": "standard",
      "expected_behavior": "answer",
      "expected_answer_patterns": ["(?i)\\b14\\.3\\s*(us\\s*)?gal(lons?)?\\b"],
      "expected_source": {
        "filename": "private_manual.pdf",
        "page": 2
      }
    }
  ]
}
```

Allowed categories:

- `exact_value`
- `table_spec`
- `missing_evidence`
- `lost_in_middle`
- `multi_hop`
- `summary`
- `retrieval_only`

Allowed `expected_behavior` values:

- `answer`: the response should match at least one expected regex when patterns
  are provided.
- `abstain`: the response should contain an abstention phrase such as "not
  enough information", "not found", or "cannot determine".

`input_files` are resolved relative to the repo root. Use
`Benchmarks/Fixtures/` for private local documents. That folder is git-ignored.

## Running

Validate a manifest without building or launching the app:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/rag_validation_sample.json --dry-run
```

## Ad Hoc Document Studio

For document-specific testing without hand-writing a manifest, start the local
studio on this Mac:

```bash
python3 scripts/rag_benchmark_studio.py --open
```

If `--open` is blocked by your shell session, open this URL manually:

```text
http://127.0.0.1:8765/
```

The studio page lets you drop one or more local documents, add question rows,
choose quality/runtime settings, and press **Run Benchmark**. It writes the
uploaded files and generated manifest under `BenchmarkRuns/<run-id>/`, then
invokes `scripts/run_rag_benchmarks.py` with the existing debug validation
harness. The page polls the local server for progress and links directly to the
run dashboard, `results.json`, and generated manifest.

By default the studio uses:

- target runtime: this MacBook, through the Debug Mac Catalyst destination
- benchmark entitlement: `lifetime`
- PCC consent: `allow`
- app refresh limit: disabled through the runner default

Note: the Mac runtime here is an App Catalyst evaluation path, not a separate native macOS app target.

The Debug configuration enables Mac Catalyst for benchmarking. The runner uses
that path when you choose `--runtime mac`, copies uploaded documents into the
app's Mac container, launches the debug harness locally, then copies the report
and trace back into `BenchmarkRuns/<run-id>/`.

Run the benchmark on this MacBook directly:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/rag_validation_sample.json --open-dashboard
```

The runner defaults to `--runtime mac` in this repo. Pass `--runtime simulator`
or `--runtime device` only when you explicitly want those targets.

Run the benchmark on an available iOS Simulator:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/rag_validation_sample.json \
  --runtime simulator
```

Run the benchmark on a connected physical iPhone or iPad:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/rag_validation_sample.json \
  --runtime device \
  --device "iPhone 16 Pro Max" \
  --open-dashboard
```

Useful options:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/rag_validation_sample.json \
  --runtime device \
  --device "iPhone 17 Pro" \
  --output-dir BenchmarkRuns \
  --timeout-seconds 420
```

Benchmark launches preset Apple PCC consent to `allow` and benchmark entitlement
to `lifetime` by default. That keeps fresh debug installs off the consent sheet
and out of the free-tier 5-document cap while the benchmark measures RAG
behavior. To exercise the normal user prompt path instead:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/rag_validation_sample.json \
  --runtime device \
  --pcc-consent default
```

Use `--pcc-consent deny` only when testing expected no-cloud behavior.
Use `--benchmark-entitlement current` to leave the app's existing debug
entitlement state alone, or `--benchmark-entitlement free` when intentionally
testing free-tier quota behavior.

The runner builds `OpenIntelligence` in Debug by default and launches one
isolated app run per case on the selected Mac, simulator, or device runtime.

The old reinstall-after-5-files workaround is still available, but it is no
longer the default:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json \
  --runtime device \
  --benchmark-entitlement free \
  --app-refresh-file-limit 5
```

The entitlement preset and refresh option are debug-harness only. They do not
change `QuotaPolicy`, `RAGService`, retrieval, ranking, generation, or
verification behavior.

Builds use reusable derived data at `/tmp/openintelligence-rag-bench/DerivedData`
so later runs do not pay a full clean-build cost every time. Use
`--derived-data` to override it. With `--runtime mac`, the runner builds for
Xcode's Mac Catalyst destination, copies each case's fixture files into the
app's Mac container, launches the debug harness locally, then copies the report
and trace back into
`BenchmarkRuns/<run-id>/cases/<case-id>/storage/`. With `--runtime device`, the
runner builds with the generic iOS device destination, installs through
`xcrun devicectl`, and uses the app data container on the connected device.

If Xcode gets stuck in simulator/device discovery, cap the build step:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/rag_validation_sample.json \
  --build-timeout-seconds 600
```

Important runtime limitation: answer-generation cases that reach Apple
Foundation Models should run with `--runtime mac` on this Apple silicon Mac or
`--runtime device` on a supported physical device. The iOS Simulator can still
exercise build/install/ingestion plumbing, but it cannot complete Foundation
Models generation. In that case the report is still preserved, but the case
fails with the harness error.

The PCC consent and entitlement presets are debug-harness only. PCC writes the
same `cloudConsent.applePCC` app setting that the consent sheet persists, and
the entitlement preset seeds the Debug app's entitlement defaults before the
benchmark `RAGService` instance is created. Neither changes production app
behavior.

Open the visual dashboard after a run:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/rag_validation_sample.json --open-dashboard
```

Add auto-refresh while a run is still writing partial results:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/rag_validation_sample.json --watch-dashboard
```

To open the auto-refreshing dashboard at the start of a real run, combine both:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/rag_validation_sample.json --watch-dashboard --open-dashboard
```

The newest run is always available at:

```text
BenchmarkRuns/latest/dashboard.html
```

## Output

Each run writes:

- `BenchmarkRuns/<run-id>/results.json`: machine-readable results.
- `BenchmarkRuns/<run-id>/summary.md`: human-readable summary table.
- `BenchmarkRuns/<run-id>/dashboard.html`: local visual dashboard.
- `BenchmarkRuns/latest/dashboard.html`: redirect to the newest dashboard.
- `BenchmarkRuns/<run-id>/cases/<case-id>/storage/ValidationOutput/rag_validation_report.txt`
- `BenchmarkRuns/<run-id>/cases/<case-id>/storage/ValidationOutput/pipeline_trace.log`
- `BenchmarkRuns/<run-id>/cases/<case-id>/simctl_stdout.log` or `devicectl_stdout.log`
- `BenchmarkRuns/<run-id>/cases/<case-id>/simctl_stderr.log` or `devicectl_stderr.log`

The dashboard shows totals, pass rate, every case's category/query/expected
behavior/status, confidence, retrieved chunk count, latency, failure reason,
response preview, retrieved sources, exact input files used, raw artifact links,
and comparison against the previous `results.json` in the output directory.

Scoring currently checks:

- expected answer regex matched
- expected source filename/page appeared in retrieved chunks when provided
- abstention detected when expected
- confidence score captured
- retrieved chunk count captured
- launch-to-report latency captured

Cases with missing local fixture files are marked `skipped`, not failed.

If the runner prints `Passed 0/0 scored cases, failed 0, skipped N`, no real
benchmark ran. That usually means the sample manifest is still pointing at
placeholder private fixture names. Add local documents under
`Benchmarks/Fixtures/` or edit `input_files` to point at absolute local paths.

## Research Fixture Packs

Create the smallest useful local research-style pack:

```bash
python3 scripts/prepare_rag_research_fixtures.py --preset tiny
```

That writes:

```text
Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json
```

Then run it:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json --open-dashboard
```

For answer-generation scoring on your connected iPhone:

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json \
  --runtime device \
  --device "iPhone 16 Pro Max" \
  --open-dashboard
```

The tiny preset creates 20 local cases:

- 5 exact-value cases
- 5 retrieval-only cases
- 5 multi-hop cases
- 3 synthetic lost-in-the-middle cases
- 2 missing-evidence cases

The prep script also has small adapter hooks for FinanceBench, BEIR, Vectara
Open RAGBench, MultiHop-RAG, QASPER, DocVQA, and RAGTruth. These are adapted
fixtures, not full official benchmark reproductions. Some datasets require
manual download or license/terms acceptance, and many public RAG benchmarks are
JSON/corpus/qrels based rather than raw PDFs.

## Limitations

- This is a local debug harness for this Mac, Simulator, or a connected physical device,
  not a production telemetry system.
- It scores the plain text validation report, so it depends on the current
  report format.
- It checks whether expected source files appear in retrieved chunks, not full
  citation faithfulness.
- It measures wall-clock latency around launch/report creation, not internal
  per-stage timings.
- It does not create or commit private fixtures.

The next useful improvement is adding a structured JSON output directly from
`DebugRAGValidationHarness` so the runner no longer has to parse the text report.
