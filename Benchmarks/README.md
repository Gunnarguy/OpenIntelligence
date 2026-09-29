> ⚠️ **`scripts/run_rag_benchmarks.py` no longer exists.** It was removed in `abd1e3b`
> (2026-07-08) when the harness moved in-app as the RAG validation dashboard. Every
> command below that invokes it will fail. They are preserved because the flags and
> workflows document intent that has not been reimplemented yet.
>
> **What works today:**
> - `python3 scripts/run_quality_matrix.py --app <path>` — runs every case under every
>   quality mode and reports the deltas. This is the supported entry point.
> - The in-app validation dashboard (`ValidationDashboardView`), which drives the same
>   `DebugRAGValidationHarness` with a live UI runloop.
>
> `scripts/rag_benchmark_studio.py` is also broken for the same reason: its `RUNNER`
> constant points at the removed script.

---

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
  "pool": ["Benchmarks/Fixtures/distractor_manual.pdf"],
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
      },
      "expected_sources": [
        {"filename": "private_manual.pdf", "page": 2}
      ]
    }
  ]
}
```

Three more fields are read by `scripts/run_quality_matrix.py` (added here 2026-09-29):

- `pool` (top level, optional): repository-relative paths ingested for every case, so retrieval has
  distractors to beat. `--pool-limit N` keeps the case's own documents and fills the remaining slots
  in manifest order. `qasper_external_v1` declares a 40-paper pool; `tiny_research_suite` has none.
- `expected_sources` (per case, optional): every document the answer needs, as `filename`/`page`
  objects. All of them are passed as retrieval ground truth; without the list the runner falls back
  to `expected_source.filename`. Cases whose `expected_behavior` is `abstain` are not
  retrieval-scored.
- `expected_evidence` (per case, optional): objects whose `excerpt` is matched against the retrieved
  chunk text, to report whether the answer's passage reached the model.

`[evidence_level: code_verified, confidence: high, evidence_source: scripts/run_quality_matrix.py:452 (expected_evidence), :647-657 and :1101 (pool), :696-705 (expected_sources); top-level and case keys of Benchmarks/ResearchFixtures/*/manifest.json, read 2026-09-29]`

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

See `Docs/ai/RUNBOOK.md`, section "## Retrieval benchmark": how to build the unsigned macOS
Debug app the harness needs, and the `scripts/run_quality_matrix.py --app <path>` commands, with
`--manifest` for the QASPER pack (the tiny suite is the default). Replaced 2026-09-29: this section used to show
`scripts/run_rag_benchmarks.py --dry-run`, which was removed in `abd1e3b`; the old text is in
`git log -p -- Benchmarks/README.md`.

## Ad Hoc Document Studio

> **Historical (2026-09-29). Nothing in this section works today.** `scripts/rag_benchmark_studio.py`
> still points its `RUNNER` at the removed `scripts/run_rag_benchmarks.py` (line 35), and the Mac
> Catalyst path it describes is gone: the app target sets `SUPPORTS_MACCATALYST = NO` in both Debug
> and Release (`OpenIntelligence.xcodeproj/project.pbxproj:795`, `:860`) and builds for native macOS
> instead. Kept for the flags and workflows it records. `[evidence_level: code_verified,
> confidence: exact, evidence_source: scripts/rag_benchmark_studio.py:35; project.pbxproj:794-796,
> 859-861; ls scripts/run_rag_benchmarks.py (absent), 2026-09-29]`

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
*(Historical: the app now builds for native macOS and Catalyst is off; see the note at the top of this section.)*

*(Historical.)* The Debug configuration enables Mac Catalyst for benchmarking. The runner uses
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
Xcode's Mac Catalyst destination (historical: Catalyst is off), copies each case's fixture files into the
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

See `Docs/ai/RUNBOOK.md`, section "## Retrieval benchmark": `scripts/run_quality_matrix.py` writes
`BenchmarkRuns/<timestamp>-matrix/` with `report.md`, `results.json` and a per-case report under
`reports/`, and `BenchmarkRuns/` is gitignored, so no run survives a fresh clone. What each run
tested and settled goes in `BenchmarkRuns/LEDGER.md`. Replaced 2026-09-29: this section described
the output and scoring of the removed `scripts/run_rag_benchmarks.py` (dashboards, `summary.md`,
`BenchmarkRuns/latest/`); the old text is in `git log -p -- Benchmarks/README.md`.

## Research Fixture Packs

See `Benchmarks/ResearchFixtures/README.md` for which pack to use (`qasper_external_v1` for
measuring anything, `tiny_research_suite` for smoke checks) and for licensing, and
`Docs/ai/RUNBOOK.md`, section "## Retrieval benchmark", for running them.
`python3 scripts/prepare_rag_research_fixtures.py --preset tiny` is what generated the tiny pack.
Running it deletes and rewrites the tracked `tiny_research_suite/` folder (`ensure_clean_pack`,
with `--overwrite` on by default), so diff the result before keeping it.
Replaced 2026-09-29: this section ran the packs with the removed `scripts/run_rag_benchmarks.py`;
the old text is in `git log -p -- Benchmarks/README.md`.

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
