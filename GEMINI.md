# Gemini / Antigravity Specific Instructions

When operating via Google Gemini or the Antigravity IDE/desktop app (2.0+), adhere strictly to these operational guardrails.

## Antigravity 2.0 wiring (read this first)
This workspace is pre-configured for Antigravity's native customization system:

- **Always-on rules** live in `.agents/rules/`:
  - `00-repoos-routing.md` — mandatory RepoOS task routing, forbidden-file boundaries, stop conditions.
  - `01-docs-and-notion-sync.md` — automatic, unprompted documentation + Notion roadmap sync triggers (path → docs table, exact Notion schema).
- **Workflows** live in `.agents/workflows/` and are invoked as slash commands:
  - `/update-docs` — sync all affected docs (incl. Mermaid diagrams) to the current diff.
  - `/sync-notion` — update the OpenIntelligence Roadmap DB (`37f49a74-d54f-81b7-9424-dae1288c0043`).
  - `/finalize` — full close-out pipeline: docs → Notion → build/test gate → explicit-path commit → single-confirmation push.
- If your Antigravity build only reads the legacy `.agent/` directory (pre-2.0 default), mirror these files into `.agent/rules/` and `.agent/workflows/`.
- These rules apply even with Auto-continue enabled: Auto-continue may carry you through a pipeline's steps, but it never overrides the two hard pauses — `PROCEED: IMPLEMENT` before first source edit, and the yes/no before `git push`.

The single source for "what may I edit, what must I read, what must I update": `Docs/RepoOS/00_REPO_COMMAND_CENTER.md`, `Docs/RepoOS/01_TASK_ROUTER.md`, and `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`. Route every task through them without being asked.

## Operational guardrails
1. **Use an artifact-first workflow**: Prioritize generating structured CSVs or Markdown artifacts in the `Docs/AuditArtifacts/` directory over verbose chat responses.
2. **Use phase gates for audit/governance work**: Never skip ahead. Execute exactly one phase at a time and wait for user approval. (For routine feature work, the RepoOS router + `/finalize` pipeline govern instead; the two hard pauses above always apply.)
3. **Sub-agents**: Use sub-agents (AgentKit/dynamic subagents) only if their outputs are evidence-backed and deterministically verifiable. Subagents inherit these rules — a subagent may not touch a forbidden file its parent couldn't.
4. **Model Selection**:
   - Use the fast/Flash tier (high reasoning) for broad extraction, line counts, and inventory generation.
   - Use the Pro tier (high reasoning) for architecture synthesis, contradiction resolution, and final design decisions.
5. **No self-verification**: Do not self-verify your own outputs as complete or final.
6. **No "VERIFIED" demands**: Do not tell the user to paste `VERIFIED: ...` back to you.
7. **Correct Handoff**: At the end of an audit phase, instruct the user with:
   `Review Phase X artifacts. If acceptable, paste: NEXT PHASE: Phase Y.`
8. **Treat prior artifacts as inputs**: Generated artifacts from previous phases are contextual inputs, not unquestioned universal truths. Always cross-reference with actual codebase reality. `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` outranks every other document.
9. **Re-verify suspicious symbols**: If a previous artifact claims a relationship between symbols (e.g., `RAGEngine`, `VectorDatabase.insert`), actively verify those symbols exist with code search before propagating them to new documentation.
10. **Docs and roadmap are part of the task**: Per `.agents/rules/01-docs-and-notion-sync.md`, a code change without its doc + Notion sync in the same turn is an incomplete task. Do not end the turn, and do not ask whether to update them — update them.
11. **Phase-state guard**: Evidence Threads Phases 1A–1D are complete (`Docs/AuditArtifacts/Implementation/phase_1b_1c_1d_post_implementation_verification.md`). Historical gate files (`Docs/AuditArtifacts/FinalReview/*`, `NEXT_PHASE_GATE.md`) are records, not instructions.
