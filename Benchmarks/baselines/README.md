# Comparison baselines

## Why this exists

Until 2026-08-21 there was no way to answer "is this release better than the last one." Benchmark
runs existed from before v4.9 shipped, but none carried a `run_config.json`, and `--seed`,
`--sampling` and `--temperature` did not exist yet — so those runs drew an unseeded sample and could
not be differenced against anything. `qasper-overnight` (2026-08-12, 83 cases) is the clearest
example: real data, uncomparable.

## `v4.9.0-measurement-backport.patch`

Applies to a **detached worktree at tag `v4.9.0`**, nothing else. Two files, and it changes only
which sample is drawn:

- `DebugRAGValidationHarness.seedSamplingOverridesIfNeeded()` — reads `--rag-validation-sampling`,
  `--rag-validation-seed`, `--rag-validation-temperature` into the same `UserDefaults` keys 5.0 uses.
- `LLMService` — applies them at the single point an `InferenceConfig` becomes `GenerationOptions`.

**Retrieval, ranking, evidence selection and prompt construction are untouched**, which is what makes
the comparison attributable to v4.9's pipeline rather than to sampling noise.

## Recreating the 4.9 arm

`/private/tmp` is cleared on reboot, so the worktree and its build are expected to disappear. Rebuild
in about ten minutes:

```bash
git worktree add --detach /private/tmp/oi-49 v4.9.0
git -C /private/tmp/oi-49 apply "$PWD/Benchmarks/baselines/v4.9.0-measurement-backport.patch"
cd /private/tmp/oi-49 && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -scheme OpenIntelligence -destination "platform=macOS" -configuration Debug \
  -derivedDataPath /private/tmp/oi-dd-49 -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

If `git worktree add` refuses because a stale entry survives a reboot, run `git worktree prune`.

## Before you run anything, back up the real library

The harness ingests into `~/Library/Application Support/OpenIntelligence` regardless of
`--rag-validation-storage`, because `WorkspaceSyncService` resolves through
`applicationSupportRoot()` which does not consult the override. Its own reset is **partial**: it
restores `documents_metadata.json` but not `containers.json`, and it deletes `vector_database_*`
files that do not match a live container id.

Measured on 2026-08-21, a 25-case run left the library holding **253 documents and 81 vector stores**
against the 15 documents and 3 stores it started with. Take a full copy first and restore afterwards:

```bash
cp -a ~/Library/"Application Support"/OpenIntelligence /private/tmp/oi-library-backup
# ... run ...
rm -rf ~/Library/"Application Support"/OpenIntelligence
cp -a /private/tmp/oi-library-backup ~/Library/"Application Support"/OpenIntelligence
```

## Which flags to use

**To describe the product**, pass no `--temperature`. The app clamps `ragOptimized`'s 0.7 down to
0.4 via `min(config, qualityMode.temperature)` (`RAGService.swift:12745`), and to 0.2 on the
cautious and high-accuracy paths. `--temperature` is applied downstream of every clamp, so passing
0.7 forces the model *hotter than the app ever runs it*.

**To compare two builds**, pin both arms to the same value and record which. `baseline-49` and the
5.0 runs it is compared against were all pinned to 0.7, so that delta is attributable to code — but
none of those runs describes the shipped product.

Keep `--seed`. It does not change the distribution, only makes the draws repeatable.
