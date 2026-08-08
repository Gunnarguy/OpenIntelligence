# Claude Context OS V2

> Universal repository bootstrap and operating protocol for Claude Code, current through August 7, 2026.
>
> **Human usage:** Put this file in the root of a repository and tell Claude Code: **"Read and implement `CLAUDE_CONTEXT_OS_V2.md` completely for this workspace."**
>
> This is an installation specification, not permanent startup context. After successful installation, keep it for auditability or move it to `docs/ai/bootstrap/`; do not import this whole file into `CLAUDE.md`.

---

# 0. Mission

You are the context governor for this repository.

Your job is to make this project reliably resumable by a fresh Claude Code session with minimal context overhead and without requiring the user to repeatedly explain the repository, prior conversations, decisions, current objective, or next steps.

Optimize for:

1. **Minimum sufficient context**, not maximum memory.
2. **Deterministic recoverability**, not transcript preservation.
3. **Progressive disclosure**, not loading the repository into every session.
4. **Repository-local truth**, not cross-project contamination.
5. **Autonomous maintenance**, while preserving user control and existing project behavior.
6. **Native Claude Code primitives first**, custom machinery only where it provides measurable value.
7. **Version-aware behavior**. Never assume a Claude Code feature exists because this document mentions it. Detect the installed capabilities before configuring them.

A fresh agent should normally require only:

- repository identity,
- branch/worktree state,
- active objective,
- material blockers,
- last verified state,
- exact next action,
- and selectively loaded domain knowledge.

Do not attempt to preserve raw reasoning or entire conversation transcripts as project memory.

---

# 1. Non-negotiable operating model

Classify persistent information before storing it.

| Information | Correct home |
|---|---|
| Universal repository invariants and commands | `CLAUDE.md` |
| Personal, unshared project preferences | `CLAUDE.local.md` |
| File/path-specific rules | `.claude/rules/*.md` with `paths` frontmatter |
| Repeatable procedures | `.claude/skills/<name>/SKILL.md` |
| Current execution state | `docs/ai/STATE.md` |
| Project purpose and stable constraints | `docs/ai/PROJECT.md` |
| Architecture and boundaries | `docs/ai/ARCHITECTURE.md` |
| Non-reconstructable decisions and rationale | `docs/ai/DECISIONS.md` |
| Setup, test, deploy, recovery procedures | `docs/ai/RUNBOOK.md` |
| Learned recurring repository quirks | Claude Code auto memory |
| Large exploration results needed only transiently | isolated subagent context |
| Parallel write tasks in one repository | separate git worktrees |
| Coordinated independent agents | Agent Teams when supported and justified |
| External systems/tools | MCP when already configured or clearly useful |
| Ephemeral reasoning | current conversation only |

Do not duplicate the same fact across several persistence layers unless there is a concrete operational reason.

The hierarchy of authority is:

1. User's current explicit instruction.
2. Enforced security/configuration policy.
3. Repository source, tests, build configuration, CI, schema, and version-controlled evidence.
4. Durable project documentation.
5. Claude Code instructions/rules.
6. Auto memory and agent memory.
7. Historical summaries.

When these conflict, prefer the higher-authority source and repair stale lower-authority state.

---

# 2. Compatibility and capability audit

Before changing anything, inspect the environment.

Determine at minimum:

- repository root and VCS type,
- current branch or detached HEAD,
- whether this is a git worktree,
- dirty working-tree state,
- Claude Code version if discoverable,
- existing `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, and other agent instruction files,
- existing `.claude/settings.json` and `.claude/settings.local.json`,
- existing `.claude/rules/`, `.claude/skills/`, `.claude/agents/`, hooks, plugins, and MCP configuration,
- whether auto memory is enabled, explicitly disabled, or unknown,
- whether the repository already implements an equivalent context system,
- available build/test/lint/typecheck commands,
- monorepo boundaries,
- secrets or sensitive generated files that must never be persisted.

If supported, prefer native Claude Code initialization/import behavior over reinventing it:

- `/init` can analyze a repository and generate or improve project instructions.
- Newer Claude Code versions can use the multi-phase init flow to configure CLAUDE.md, skills, and hooks.
- `/import` can import supported instructions and agent configuration from other coding tools.

Do **not** run an interactive command that blocks unattended execution if equivalent inspection can be performed directly. Use native behavior as a source of truth and a design reference, not as an excuse to stop and ask the user to configure things manually.

If a feature in this specification is unsupported by the installed Claude Code version, degrade gracefully and record the omission in the final report. Never install invalid configuration just to satisfy this document literally.

---

# 3. Preserve before modifying

This installation must be additive and conservative.

Never blindly replace:

- `CLAUDE.md`,
- `.claude/settings.json`,
- hooks,
- rules,
- skills,
- MCP servers,
- agent definitions,
- CI configuration,
- application code,
- user-created project documentation.

Before modifying an existing configuration file:

1. Read and understand it.
2. Preserve unrelated behavior.
3. Merge structurally where possible.
4. Avoid duplicate hooks, duplicate rules, and contradictory instructions.
5. Back up or use version control when a merge is non-trivial.
6. Never silently weaken existing security or permission policy.

If this repository already has a stronger equivalent mechanism, integrate with it instead of layering a competing system on top.

---

# 4. Create the durable project knowledge plane

Create `docs/ai/` if an equivalent structured project knowledge location does not already exist.

Prefer this minimal structure:

```text
docs/ai/
├── INDEX.md
├── PROJECT.md
├── ARCHITECTURE.md
├── STATE.md
├── DECISIONS.md
└── RUNBOOK.md
```

Do not create empty bureaucracy. If a file would contain no useful evidence-supported information, keep it extremely short and mark what must be verified later.

## `docs/ai/INDEX.md`

Purpose: navigation, not duplication.

Include:

- one-sentence project identity,
- links to the five durable documents,
- a one-line statement describing when each document should be consulted,
- last context-system audit date.

## `docs/ai/PROJECT.md`

Persist only stable project facts:

- purpose,
- primary users,
- in-scope/out-of-scope behavior,
- major constraints,
- supported platforms/environments,
- critical dependencies,
- source-of-truth locations.

Do not copy the README unless information is both important and not cheaply discoverable.

## `docs/ai/ARCHITECTURE.md`

Capture durable system structure:

- major components,
- boundaries,
- data flow,
- persistence layers,
- externally coupled systems,
- security-sensitive boundaries,
- non-obvious implementation constraints.

Reference source files instead of reproducing them.

## `docs/ai/DECISIONS.md`

Use append-oriented decision records for decisions whose rationale cannot be reconstructed from code.

Each meaningful entry should contain:

- date,
- decision,
- context,
- alternatives considered if known,
- rationale,
- consequences,
- superseded-by link if later replaced.

Do not record trivial coding choices.

## `docs/ai/RUNBOOK.md`

Record verified operational procedures:

- setup,
- build,
- test,
- lint/typecheck,
- local run,
- deployment when applicable,
- migrations,
- common recovery steps,
- required external services.

Commands must be derived from repository evidence or successfully verified. Mark unverified commands explicitly.

## `docs/ai/STATE.md`

This is the cross-session execution handoff, not a diary.

Keep it concise and overwrite stale execution details rather than appending endlessly.

Use this structure unless the project has a better equivalent:

```markdown
# Current State

Updated: YYYY-MM-DD HH:MM timezone
Branch/worktree: ...
Last verified commit: ...

## Objective
One concrete current objective.

## Status
Short factual description of where execution stands.

## Completed
- Only work materially relevant to continuation.

## Active Constraints
- Constraints that could change the implementation decision.

## Working Set
- `path`: why it matters

## Verification
- command -> result

## Blockers / Unknowns
- blocker or unknown -> exact verification path

## Exact Next Action
One executable next action a fresh session can take immediately.
```

Rules for `STATE.md`:

- Keep the active handoff ideally below ~150 lines.
- Do not paste conversation summaries.
- Do not repeat stable architecture already stored elsewhere.
- Do not claim tests passed unless they were actually executed.
- Record uncommitted changes if they are part of the current objective.
- When objective changes, replace obsolete state.
- When work completes, state that explicitly and point to the next meaningful objective or mark idle.

---

# 5. Build a minimal `CLAUDE.md` control plane

Use existing project instructions if they are already high quality.

Otherwise create or carefully augment `CLAUDE.md`.

Target **well below 200 lines**. Smaller is better.

Its function is to tell Claude how to orient and where to find detail, not to contain the detail itself.

It should encode only repository-wide invariants such as:

```markdown
# Repository Operating Protocol

## Orientation
- Treat repository source, tests, CI, and configuration as authoritative.
- Read `docs/ai/STATE.md` at the start of substantive work when present.
- Load `docs/ai/ARCHITECTURE.md`, `PROJECT.md`, `DECISIONS.md`, or `RUNBOOK.md` only when the task requires them.
- Do not load all project documentation by default.

## Context Governance
- Persist active execution state in `docs/ai/STATE.md`.
- Persist non-reconstructable architectural/product rationale in `docs/ai/DECISIONS.md`.
- Put repeatable procedures in skills rather than expanding this file.
- Put path-specific requirements in `.claude/rules/`.
- Use auto memory for recurring learned quirks, not canonical project truth.
- Remove stale or contradictory context when discovered.

## Execution
- Prefer isolated Explore/subagents for broad repository research whose intermediate output is not needed in the main context.
- Use separate worktrees for parallel write-capable sessions in the same repository.
- Verify material changes with the repository's actual test/lint/typecheck commands before claiming completion.

## Handoff
- Before ending substantial unfinished work, before compaction where feasible, and after major objective changes, make `docs/ai/STATE.md` sufficient for a fresh session to continue without this transcript.
```

Then add only project-specific invariant commands and conventions that are genuinely needed every session.

If `AGENTS.md` is canonical for a multi-agent repository, integrate it carefully. Do not duplicate hundreds of lines into CLAUDE.md when an appropriate supported import strategy already exists, but remember that imported files consume startup context too.

---

# 6. Use path-scoped rules for conditional context

Create `.claude/rules/` only where conditional rules will materially reduce context or improve correctness.

Examples:

```text
.claude/rules/
├── ios.md
├── api.md
├── database.md
├── tests.md
└── security.md
```

Use `paths` frontmatter for rules that apply only to matching files.

Example:

```markdown
---
paths:
  - "src/api/**/*.ts"
  - "tests/api/**/*.ts"
---

# API Rules
- Validate external input at the boundary.
- Preserve the repository's standard error shape.
- Update contract tests when public behavior changes.
```

Avoid unconditional rules unless they truly apply to every task, because unconditional project rules are startup context.

Do not manufacture domain rules from assumptions. Derive them from code, tests, CI, existing docs, or explicit user requirements.

---

# 7. Install only high-value skills

Skills are procedures and selectively loaded knowledge, not project state databases.

Create project-local skills only when the procedure will recur.

Recommended baseline skills, if they add value:

```text
.claude/skills/
├── project-orient/SKILL.md
├── project-handoff/SKILL.md
└── project-context-audit/SKILL.md
```

## `project-orient`

Purpose: rapidly reconstruct task-relevant repository context without contaminating the main context.

If supported, configure it to run in an isolated/forked context or delegate to an Explore-like subagent.

Workflow:

1. Read `STATE.md`.
2. Inspect only repository areas relevant to the requested task.
3. Read durable docs only as needed.
4. Resolve conflicts against source/test/config evidence.
5. Return a compact orientation containing:
   - relevant architecture,
   - files likely involved,
   - constraints,
   - risks,
   - recommended next action.

Do not return a repository encyclopedia.

## `project-handoff`

Purpose: make a fresh conversation capable of continuing correctly.

Workflow:

1. Identify the active objective.
2. Inspect git diff/status and relevant files.
3. Capture verified work and test results.
4. Capture unresolved blockers and unknowns.
5. Move durable rationale into `DECISIONS.md` if appropriate.
6. Update `STATE.md` with the exact next action.
7. Remove stale state.
8. Validate that the handoff can stand without the transcript.

## `project-context-audit`

Purpose: periodically remove context entropy.

Check for:

- stale state,
- duplicated facts,
- contradictory instructions,
- bloated `CLAUDE.md`,
- unconditional rules that should be path-scoped,
- procedures that should become skills,
- canonical facts incorrectly stored only in auto memory,
- dead links and renamed files,
- obsolete decisions not marked superseded,
- accidental secret material.

Repair safe issues directly and report ambiguous ones.

Do not create additional skills unless there is a concrete repeatable workflow.

---

# 8. Configure auto memory correctly

Claude Code auto memory is useful for repository-specific learned patterns, build quirks, debugging discoveries, and recurring corrections.

Do not use it as the sole source of truth for:

- active objective,
- architectural contracts,
- product requirements,
- security policy,
- exact continuation state,
- decisions that teammates must review.

If auto memory is enabled, keep it enabled unless this repository has an explicit reason not to.

If explicitly disabled by project/user configuration, respect that choice.

Never copy secrets, credentials, tokens, private keys, regulated data, or unnecessary personally identifying information into memory.

When a memory conflicts with version-controlled truth, update or remove the stale memory if the available Claude Code interface permits it safely.

---

# 9. Add lifecycle automation using native hooks

Use hooks only when supported and when deterministic lifecycle behavior adds value.

Hooks execute with user-level privileges. Keep scripts small, auditable, repository-local, and free of network access unless there is an explicit repository requirement.

Never install destructive hooks.

## SessionStart

Install a fast `SessionStart` hook when it improves orientation.

Its output should be bounded and normally include only:

- repository/worktree identity,
- branch,
- HEAD,
- concise dirty-state summary,
- whether `STATE.md` exists and appears stale,
- active objective,
- exact next action,
- warning if durable state and git state diverge materially.

Do **not** dump entire project documents into startup context.

Claude Code supports SessionStart sources such as startup, resume, clear, compact, and fork. Ensure the hook behaves sensibly for each supported source.

If a hook creates or updates skills during SessionStart and the installed version supports skill reloading, request a skill rescan instead of forcing a new session.

## PreCompact

Use `PreCompact` as a checkpoint trigger, not as a transcript archive.

Before compaction, when there is meaningful unfinished work:

- make sure `STATE.md` reflects the current objective,
- preserve non-reconstructable decisions,
- capture verified test status,
- capture exact next action.

Do not routinely block automatic compaction. A context system that prevents compaction until the window fails is worse than one that writes a good checkpoint.

## PostCompact

If supported and useful, use `PostCompact` only for lightweight verification that durable state is still coherent. Do not persist the generated compact summary wholesale.

## Stop

A Stop hook may detect that substantive repository changes occurred without a corresponding durable handoff.

If it asks Claude to continue and repair the handoff:

- check `stop_hook_active` and never create an infinite loop,
- ignore sessions that still have expected background work or scheduled continuation when appropriate,
- allow stopping after one bounded repair attempt,
- never block the user indefinitely,
- do not require handoff for trivial read-only questions.

A Stop hook is a safety net, not the primary workflow.

## Additional hook opportunities

Use other native lifecycle events only when the project justifies them. Examples may include:

- blocking known-dangerous commands with `PreToolUse`,
- running targeted formatting or validation after specific writes,
- watching relevant paths in supported versions,
- setup/maintenance hooks for explicit initialization workflows.

Do not create hook theater. Every hook must have a clear failure mode and a measurable benefit.

---

# 10. Use isolated agents intentionally

Subagents have separate context windows and should be used to keep expensive intermediate exploration out of the primary conversation.

Prefer an Explore/read-only agent for:

- locating an implementation,
- understanding an unfamiliar module,
- tracing data flow,
- comparing several candidate files,
- surveying tests,
- researching architecture before planning.

Use a general-purpose subagent when isolated modification or complex multi-step execution is beneficial and safe.

Create custom project subagents only if a recurring role requires specialized instructions, tools, permissions, or memory.

If custom subagent memory is supported, use **project/local scope** for repository-specific learnings unless there is a strong reason to share across repositories.

Do not delegate merely to appear agentic. Delegation is justified when it reduces primary-context pollution, enables parallelism, isolates risk, or provides useful specialization.

---

# 11. Parallelism policy

For multiple independent repositories, each repository is its own context boundary.

For parallel work **inside the same git repository**, prefer isolated worktrees for write-capable sessions.

Example capability where supported:

```bash
claude --worktree feature-auth
```

Do not allow two independent write-capable sessions to casually edit the same checkout.

Use native Agent Teams when:

- the installed version supports them,
- the work decomposes into independently useful tasks,
- coordination between agents is actually needed,
- shared task state or peer messaging reduces human orchestration.

Use subagents instead when:

- one parent agent should remain in control,
- only a compact result needs to return,
- independent peer coordination is unnecessary.

Use worktrees for file isolation, and use agents/teams for cognitive or execution decomposition. They solve different problems and can be combined.

---

# 12. MCP and external tools

Audit existing MCP configuration.

Do not automatically add external services just because MCP exists.

Add or recommend an MCP server only when the repository has a recurring need that cannot be served well by built-in tools or existing integrations, such as:

- issue tracker access,
- production observability,
- database metadata,
- design system source of truth,
- deployment platform,
- internal documentation.

Never embed credentials in repository-tracked configuration.

Prefer least-privilege permissions.

---

# 13. Context budget policy

Treat context as a scarce execution resource.

Apply these rules:

1. Do not import large files into `CLAUDE.md` merely for organization.
2. Prefer path-scoped rules for domain-specific requirements.
3. Prefer skills for procedures and large references needed only sometimes.
4. Prefer isolated subagents for broad exploration.
5. Prefer source references over copied code excerpts in durable docs.
6. Keep `STATE.md` concise.
7. Delete or supersede stale information.
8. Do not persist information that can be reconstructed cheaply and reliably.
9. Preserve information whose rationale or historical decision cannot be reconstructed.
10. Never optimize token count at the expense of losing a critical constraint.

The target is not a specific token number. The target is the lowest startup/context cost that still makes the next correct action obvious.

---

# 14. Staleness and contradiction control

On startup and during context audits, detect material drift between durable context and repository reality.

Examples:

- `STATE.md` names files that no longer exist.
- Recorded HEAD differs from the current branch by substantial work.
- A build command was renamed.
- Architecture docs describe a component removed from source.
- A decision was superseded but not marked.
- Auto memory contradicts current tests/configuration.

When evidence is clear, repair stale context autonomously.

When evidence is ambiguous, mark the uncertainty with a concrete verification path rather than guessing.

Use phrases like:

```text
Unknown: whether production still uses Redis for session storage.
Verify: inspect deployment configuration or production infrastructure source.
```

Do not turn uncertainty into invented project history.

---

# 15. Security and privacy requirements

Never persist:

- API keys,
- authentication tokens,
- passwords,
- private keys,
- raw `.env` values,
- credentials discovered in shell history,
- sensitive user data,
- secret production payloads,
- unnecessary full transcripts.

If durable context needs to mention a secret-dependent fact, record the secret's **location or environment-variable name**, not its value.

Example:

```text
Stripe credentials are provided through `STRIPE_SECRET_KEY`; never commit the value.
```

Ensure runtime checkpoint/state files containing machine-local data are gitignored where appropriate.

---

# 16. Managed Agents upgrade path

This repository bootstrap must work in ordinary Claude Code without requiring Claude Platform Managed Agents.

However, if the user is intentionally operating through Managed Agents and the environment exposes those capabilities, apply the same information taxonomy at the platform layer.

## Managed Agent definition

Treat the Managed Agent as the reusable control plane for:

- model selection,
- system prompt,
- tools,
- MCP servers,
- skills,
- permission policy.

Do not duplicate the entire repository knowledge base in the system prompt.

## Memory Stores

When a project has a dedicated Managed Agent or stable project identity, attach a project-specific memory store for long-lived learned knowledge.

Use memory stores for:

- recurring project conventions,
- lessons from prior failures,
- domain-specific learned knowledge,
- durable preferences relevant across sessions.

Keep canonical repository truth in version control when it should be reviewable by humans or coupled to code versions.

## Dreams

If Dreams are available and the memory store has accumulated sufficient history to justify consolidation, use them periodically to reorganize, deduplicate, and reconcile learned memory across selected prior sessions.

Dreams are a consolidation mechanism, not a substitute for `STATE.md`, git, tests, or architectural decision records.

Do not assume Dreams are available in local Claude Code. Never fabricate a local Dreams integration.

## Managed multiagent orchestration

Use platform multiagent orchestration for workloads where independent context-isolated agents operating in the same managed environment materially improve throughput or specialization.

Preserve the same coordination principles:

- explicit task boundaries,
- minimal shared context,
- one source of truth for project state,
- deterministic artifact ownership,
- verification before integration.

---

# 17. Repository-specific adaptation

Do not install a generic skeleton and stop.

Inspect this repository deeply enough to adapt the system.

At minimum, infer from evidence:

- what the project does,
- primary language/framework,
- build system,
- test system,
- source layout,
- CI behavior,
- persistence/data layer,
- platform/runtime constraints,
- deployment model where discoverable,
- high-risk modules,
- existing conventions,
- current branch objective from git state and existing docs when possible.

Populate durable docs with only useful findings.

Use source, tests, config, lockfiles, manifests, CI workflows, git history, and existing documentation as evidence.

Do not alter application behavior during bootstrap unless the user explicitly asks for application changes.

---

# 18. Idempotency

Running this specification multiple times must be safe.

On subsequent runs:

- audit rather than duplicate,
- update stale generated context,
- preserve user-authored improvements,
- merge new hook configuration without duplicate registrations,
- avoid creating duplicate skills or rules,
- report drift,
- leave the repository cleaner than it was.

Where useful, add a short machine-readable or HTML-comment marker identifying Context OS-managed sections, but never make the marker itself required for correctness.

---

# 19. Validation requirements

Before declaring installation complete, validate the resulting system.

At minimum verify:

### Structural
- project instruction file exists or an equivalent is intentionally used,
- `STATE.md` exists and is useful,
- knowledge files referenced by instructions actually exist,
- rules use valid supported syntax,
- skills are discoverable in the installed Claude Code version,
- hook configuration is syntactically valid,
- hook script paths exist,
- local/runtime files are ignored appropriately,
- existing configuration remains intact.

### Context quality
- startup instructions are concise,
- no giant knowledge dump is permanently loaded,
- current state can be understood without the current transcript,
- exact next action is explicit,
- no obvious contradictions exist,
- unsupported claims are marked unknown.

### Safety
- no secrets were copied into durable context,
- hooks are non-destructive,
- permissions were not weakened,
- network behavior was not introduced silently.

### Operational
When possible, simulate or directly test:

- new-session orientation,
- `/clear` or equivalent fresh-context recovery,
- compaction checkpoint behavior,
- Stop-hook recursion protection,
- dirty-worktree detection,
- a worktree session if the project uses parallel work,
- skill invocation/discovery.

Do not claim a test you did not run.

---

# 20. Completion contract

Do not stop after merely creating files.

Finish with exactly one of these statuses:

## `READY`

Use only when:

- installation is complete,
- validation found no material issue,
- current project state is populated sufficiently for a fresh session,
- no user action is required for ordinary use.

## `READY WITH WARNINGS`

Use when the system is usable but one or more optional capabilities are unavailable or a non-blocking uncertainty remains.

## `BLOCKED`

Use only when a genuinely required action cannot be completed safely or the repository/environment prevents installation.

The final report should be concise and include:

```text
STATUS: READY | READY WITH WARNINGS | BLOCKED

Installed/updated:
- ...

Preserved:
- ...

Detected capabilities:
- ...

Validation:
- ...

Warnings:
- ...

Fresh-session entry point:
- Read/injected state: ...
- Exact next action: ...
```

Do not require the user to memorize a maintenance procedure.

---

# 21. Permanent behavior after installation

Once installed, operate according to this invariant:

> Maintain the minimum sufficient durable state required for another fresh agent to continue the project correctly.

Continuously route information correctly:

```text
Invariant instruction           -> CLAUDE.md
Path-specific instruction       -> .claude/rules/
Repeatable procedure            -> skill
Current execution state         -> STATE.md
Stable project truth            -> PROJECT.md / ARCHITECTURE.md
Non-reconstructable rationale   -> DECISIONS.md
Operational procedure           -> RUNBOOK.md
Recurring learned quirk         -> auto memory
Large transient exploration     -> isolated subagent
Parallel write work             -> worktree
Coordinated independent work    -> Agent Teams when justified
External capability             -> MCP when justified
Temporary reasoning             -> conversation only
```

Before storing anything, ask internally:

1. Will a future session need this?
2. Can it be cheaply reconstructed from authoritative sources?
3. Is this fact stable enough to persist?
4. Which persistence mechanism has the smallest context cost while preserving correctness?
5. Could this information become dangerous or misleading if stale?

If the answer suggests not storing it, do not store it.

---

# 22. Fresh-session behavior

A fresh Claude Code session in this repository should behave as follows without requiring the user to re-explain the project:

1. Receive minimal startup context from `CLAUDE.md`, rules, auto memory, and any SessionStart hook.
2. Read `docs/ai/STATE.md` for substantive project work.
3. Determine whether the user's new request supersedes the recorded objective.
4. Load only task-relevant durable docs and scoped rules.
5. Delegate broad exploration into isolated context when useful.
6. Execute and verify work.
7. Update durable state when the continuation point materially changes.
8. End with the project recoverable by another fresh session.

The user should normally be able to say only:

```text
Continue.
```

or provide a new task directly.

---

# 23. Bootstrap now

Implement this system **now** for the current repository.

Do not merely summarize this specification.

Do not ask the user to choose among ordinary implementation details that can be resolved safely from repository evidence.

Do not install unsupported configuration.

Do not modify application behavior.

Do preserve all existing valuable Claude/agent configuration.

Do use current installed Claude Code behavior as the compatibility authority.

Do inspect enough of the repository to make the resulting context genuinely project-specific.

Do validate the result.

Do leave the project ready for a completely fresh conversation to continue with minimal context loss.

