# Gemini / Antigravity Specific Instructions

When operating via Google Gemini or the Antigravity IDE environment, you must adhere strictly to these operational guardrails:

1. **Use an artifact-first workflow**: Prioritize generating structured CSVs or Markdown artifacts in the `Docs/AuditArtifacts/` directory over verbose chat responses.
2. **Use phase gates**: Never skip ahead. Execute exactly one phase at a time and wait for user approval.
3. **Sub-agents**: Use sub-agents only if their outputs are evidence-backed and deterministically verifiable.
4. **Model Selection**: 
   - Use Gemini 3.5 Flash (high reasoning) for broad extraction, line counts, and inventory generation.
   - Use Gemini 3.1 Pro (high reasoning) for architecture synthesis, contradiction resolution, and final design decisions.
5. **No self-verification**: Do not self-verify your own outputs as complete or final.
6. **No "VERIFIED" demands**: Do not tell the user to paste `VERIFIED: ...` back to you.
7. **Correct Handoff**: At the end of a phase, instruct the user with: 
   `Review Phase X artifacts. If acceptable, paste: NEXT PHASE: Phase Y.`
8. **Treat prior artifacts as inputs**: Generated artifacts from previous phases are contextual inputs, not unquestioned universal truths. Always cross-reference with actual codebase reality.
9. **Re-verify suspicious symbols**: If a previous artifact claims a relationship between symbols (e.g., `RAGEngine`, `VectorDatabase.insert`), actively verify those symbols exist with code search before propagating them to new documentation.
