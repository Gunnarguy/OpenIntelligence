# tiny_research_suite

        Generated small RAG fixture pack.

        Manifest:

        ```bash
        Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json
        ```

        Run:


> Note: `scripts/run_rag_benchmarks.py` was removed in `abd1e3b`. Use
> `python3 scripts/run_quality_matrix.py --app <path>` or the in-app validation
> dashboard. Until 2026-09-29 the command below still named the removed script; it now matches
> what `scripts/prepare_rag_research_fixtures.py` writes.

        The runner writes into the app's real library: back it up first and restore it afterwards, as
        `Benchmarks/baselines/README.md` describes under "Before you run anything".

        ```bash
        cp -a ~/Library/"Application Support"/OpenIntelligence /private/tmp/oi-library-backup
        python3 scripts/run_quality_matrix.py --app <path/to/OpenIntelligence.app> --manifest Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json
        ```

        Case counts:

        - exact_value: 5
- lost_in_middle: 3
- missing_evidence: 2
- multi_hop: 5
- retrieval_only: 5

        This pack is an adapted local fixture set, not a full official benchmark
        reproduction. Check each case's `source_dataset` and `license_note` in
        the manifest before sharing generated files.
