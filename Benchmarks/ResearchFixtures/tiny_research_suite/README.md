# tiny_research_suite

        Generated small RAG fixture pack.

        Manifest:

        ```bash
        Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json
        ```

        Run:

        ```bash
        python3 scripts/run_rag_benchmarks.py Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json --open-dashboard
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
