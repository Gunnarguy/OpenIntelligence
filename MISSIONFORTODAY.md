MISSIONFORTODAY Checkpoint Update

Completed Discovery:
- [x] Read `MISSIONFORTODAY.md`.
- [x] Confirmed destination repo: `/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public`.
- [x] Confirmed destination remote: `https://github.com/Gunnarguy/OpenIntelligence.git`.
- [x] Confirmed destination branch: `main`.
- [x] Confirmed destination tracked status appeared clean.
- [x] Confirmed source repo: `/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Engine`.
- [x] Confirmed source remote: `https://github.com/Gunnarguy/OpenIntelligence-Engine.git`.
- [x] Confirmed backup repo exists at `/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-backup-20260415`.
- [x] Confirmed `gitleaks` and `trufflehog` are not installed locally.
- [x] User chose clean import now, backup history audit later.

Important Findings:
- [x] Source repo has local uncommitted tracked changes that must not be overwritten:
  `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`,
  `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`,
  `Samples/SourceSDKHost/SourceSDKHost/ContentView.swift`,
  `SideProjectors.md`.
- [x] Source repo has untracked `MISSIONFORTODAY.md`.
- [x] Source contains sales/productization material to exclude: `EngineSale/`, `output/`, `Docs/PRICING_STRATEGY.md`, buyer/partner packet scripts, marketing files, generated SDK artifacts.
- [x] Public repo previously contained SideProjectors/buyer/sale framing and needed README/docs rewrite, not just a code copy.
- [x] `Samples/SourceSDKHost` was intentionally excluded because it presents source-SDK/productization validation rather than neutral public proof-of-work.
- [x] Neutral technical references were restored under `Docs/Engineering/`; buyer, pricing, release, and sale docs remain excluded.
- [x] Remaining risky phrase matches in the public repo are disclaimer/checklist text only.
- [x] Local `xcodebuild` verification was attempted twice with DerivedData under `/private/tmp`; both attempts hung before compiler child processes appeared and were stopped.
- [x] Public branch pushed: `public-engine-refresh`.
- [x] PR opened: `https://github.com/Gunnarguy/OpenIntelligence/pull/6`.
- [x] GitHub bot messages reviewed:
  Sourcery/Copilot could not review because the PR changed 332 files; Codex left two actionable P2 comments in `scripts/run_rag_benchmarks.py`.
- [x] Follow-up benchmark fixes committed and pushed on the PR branch:
  `f402f35 Fix RAG benchmark source validation`.
- [x] GitHub Actions CI passed on PR #6:
  `Build` succeeded at `https://github.com/Gunnarguy/OpenIntelligence/actions/runs/25749169632/job/75620564808`.
- [x] PR #6 merged into public `main` with squash merge commit:
  `6dc093c Refresh OpenIntelligence as public document intelligence prototype`.
- [x] Local public checkout updated to `main` at `6dc093c`.

Next Actions:
- [x] In `OpenIntelligence-Public`, create `public-engine-refresh` from latest `main`.
- [x] Run targeted source scans before copying.
- [x] Import only cleaned engineering/app state from `OpenIntelligence-Engine`.
- [x] Rewrite README and technical docs into neutral proof-of-work positioning.
- [x] Re-run risky phrase and secret scans in public repo.
- [x] Build with `xcodebuild` using writable DerivedData under `/private/tmp` attempted; local verification blocked by quiet Xcode/package-resolution hang.
- [x] Commit as `Refresh OpenIntelligence with cleaned document intelligence engine`.
- [x] Push branch and open PR titled `Refresh OpenIntelligence as public document intelligence prototype`.
- [x] Address PR feedback before merge.
- [x] Merge PR #6 into `main`.
- [ ] Optional later pass: audit backup repo history before importing any old commits.

Defaults Locked:
- Do not import backup history in the first pass.
- Do not copy `.git`, generated output, sale collateral, pricing docs, buyer packets, `.env`, DerivedData, build products, or local machine files.
- Preserve public repo identity, stars, issues, and URL.
- Do not force-push `main`.

---

You are working on my OpenIntelligence repositories.

Goal:
Restore OpenIntelligence as my main public proof-of-work repository by bringing the cleaned engineering substance from OpenIntelligence-Engine into the existing public OpenIntelligence repo, while preserving the public repo, its stars, and its discoverability.

Context:
I have multiple versions:
1. Public repo:
   - Gunnarguy/OpenIntelligence
   - This is the canonical public repo.
   - It already has GitHub stars and public traction.
   - Preserve this repo as the public destination.

2. Private engine repo:
   - Gunnarguy/OpenIntelligence-Engine
   - This contains the deeper engine/productization work.
   - It also contains too much commercial, sales, buyer-packet, SDK-sale, and partner-delivery framing.
   - The engineering work should come over.
   - The sales/productization wrapper should not.

3. Local backup repo:
   - Contains fuller commit history.
   - Do not blindly publish this history.
   - Treat it as a reference source only unless history passes a complete secret/content audit.

Primary strategy:
Use the existing public OpenIntelligence repo as the canonical repo.
Create a new branch in the public repo.
Import the cleaned engine/app state from OpenIntelligence-Engine.
Do not overwrite the public repo's .git folder.
Do not destroy stars, issues, repo identity, or public URL.
Do not force-push main unless explicitly approved.

High-level outcome:
The public repo should present OpenIntelligence as:

"An experimental Apple-native document intelligence prototype exploring local-first retrieval, source-backed answers, citations, library isolation, and AI-assisted reasoning over user-controlled files."

It should not present itself as:
- a finished commercial SDK
- a sealed binary SDK
- a production enterprise product
- a regulated healthcare tool
- a clinical decision-support system
- a buyer-ready handoff
- a company
- a product for sale

Step 1: Prepare working directories

Clone or open these locally:

- public repo as destination:
  OpenIntelligence-public

- private engine repo as source:
  OpenIntelligence-Engine

- local backup repo as reference only:
  OpenIntelligence-backup

Create a new branch in the public repo:

git checkout main
git pull origin main
git checkout -b public-engine-refresh

Step 2: Audit the private engine source before copying

Search the private engine repo for risky content before importing:

- API keys
- tokens
- secrets
- .env files
- private credentials
- personal data
- Stryker references
- Stanford references
- VA references
- hospital-specific references
- patient data
- HIPAA claims
- clinical decision-support claims
- diagnostic claims
- pricing language
- licensing language
- buyer language
- sales language
- design-partner language
- partner packet language
- founder-led sales language
- acquisition language
- handoff language
- "enterprise-ready"
- "production-ready"
- "commercial SDK"
- "sealed binary SDK"
- "buyer packet"
- "private source-distributed SDK"

Use searches like:

grep -RniE "api[_-]?key|token|secret|sk-|OPENAI|\.env|credential|password" .
grep -RniE "Stryker|Stanford|VA Palo Alto|hospital|patient|HIPAA|clinical decision|diagnostic|regulated|IFU" .
grep -RniE "buyer|partner|design partner|sales|sell|selling|pricing|license|licensing|commercial|enterprise|SDK handoff|acquisition|founder-led" .

If gitleaks or trufflehog is available, run them too:

gitleaks detect --source . --no-git
trufflehog filesystem . --no-update

Do not proceed until risky findings are either removed, rewritten, or documented.

Step 3: Decide what should not be copied

Exclude commercial/productization artifacts unless they are rewritten into neutral engineering documentation.

Do not copy these paths as-is:

- output/OpenIntelligence-SDK-Package/
- output/OpenIntelligence-Partner-Packet/
- Docs/PRICING_STRATEGY.md
- any Selling Playbook
- any Founder Sales Runbook
- any Design Partner Offer
- any buyer packet zip
- any generated commercial packet
- any internal sales collateral
- any pricing docs
- any licensing docs
- any partner-delivery docs
- build products
- DerivedData
- .env files
- xcuserdata
- local machine files
- private notes

If a file contains useful technical information, rewrite it into a neutral doc under Docs/Engineering/ instead of copying it as sales material.

Step 4: Copy the cleaned engine/app code into the public repo

Copy the actual engineering project from OpenIntelligence-Engine into OpenIntelligence-public.

Preserve useful source files such as:

- OpenIntelligence/
- OpenIntelligence.xcodeproj/
- Package.swift, if present and appropriate
- Samples/, if clean
- scripts/, if clean and useful
- Docs/ technical docs, if rewritten and safe
- tests, if present
- README assets, if clean
- demo screenshots, if safe and generic

Do not copy .git from the engine repo.

Use rsync or equivalent, excluding risky/generated/private material.

Example approach:

rsync -av \
  --exclude ".git" \
  --exclude ".env" \
  --exclude ".DS_Store" \
  --exclude "DerivedData" \
  --exclude "build" \
  --exclude "xcuserdata" \
  --exclude "output/OpenIntelligence-SDK-Package" \
  --exclude "output/OpenIntelligence-Partner-Packet" \
  --exclude "Docs/PRICING_STRATEGY.md" \
  --exclude "*SELLING*" \
  --exclude "*Selling*" \
  --exclude "*sales*" \
  --exclude "*Sales*" \
  --exclude "*BUYER*" \
  --exclude "*Buyer*" \
  --exclude "*PARTNER*" \
  --exclude "*Partner*" \
  /path/to/OpenIntelligence-Engine/ \
  /path/to/OpenIntelligence-public/

After copying, inspect git diff carefully.

Step 5: Rewrite the public README

Replace the README with a clean public-facing portfolio README.

The README should include:

- What OpenIntelligence is
- Why it was built
- What it explores
- What it does today
- Architecture overview
- Core features
- Tech stack
- Limitations
- What it is not
- Screenshots or demo link if available
- Relationship to OpenClinic, if appropriate
- Setup instructions
- Roadmap

Use this positioning:

# OpenIntelligence

OpenIntelligence is an experimental Apple-native document intelligence prototype for working with user-controlled files.

It explores local-first document ingestion, library-based organization, retrieval, source-backed answers, citations, confidence signals, and AI-assisted reasoning on Apple platforms.

This is a proof-of-concept and portfolio project. It is not a finished enterprise SDK, regulated healthcare system, clinical decision-support tool, or production-ready commercial product.

Core concepts:
- local-first document workflows
- user-controlled files
- document ingestion
- chunking and retrieval
- library or workspace isolation
- source-backed answers
- citations and evidence review
- confidence and warning signals
- Apple-native app architecture
- Swift and SwiftUI implementation

What this demonstrates:
- AI product engineering
- retrieval-oriented system design
- Apple-platform development
- practical handling of context constraints
- source-grounded answer design
- iterative prototype development

Limitations:
- experimental prototype
- not validated for regulated workflows
- not intended for clinical, legal, or safety-critical decision-making
- not guaranteed to produce complete or correct answers
- may require device-specific Apple Intelligence availability
- packaging and setup may require developer familiarity

Step 6: Rewrite technical docs

Create or update these docs:

- Docs/ARCHITECTURE.md
- Docs/RETRIEVAL_PIPELINE.md
- Docs/LIMITATIONS.md
- Docs/ROADMAP.md
- Docs/DEMO.md

Keep the docs technical and honest.

Do not include:
- pricing
- buyer language
- commercial offer language
- licensing pitch
- partner packet language
- sales scripts

Step 7: Preserve public repo value

Do not delete the public repo.
Do not create a new public repo unless there is a major blocking reason.
Do not archive the public repo.
Do not rename the public repo unless explicitly approved.
Do not force-push main without approval.

The existing public repo is valuable because it already has public traction and stars.

Step 8: Commit strategy

Default safe strategy:
Make one clean import commit on the public repo branch.

Commit message:

"Refresh OpenIntelligence with cleaned document intelligence engine"

Commit body:

"Reintroduces the current OpenIntelligence engineering work as a public proof-of-concept. Removes commercial/sales framing and positions the project as an experimental Apple-native document intelligence prototype focused on local-first retrieval, source-backed answers, citations, and library isolation."

Do not import old commit history by default.

Reason:
Old history may contain secrets, pricing experiments, private notes, sales framing, or other material that should not be public.

Step 9: Optional history recovery

Only attempt to recover selected history if specifically approved after the clean public version is ready.

If history recovery is requested:

1. Clone the local backup repo into a separate temporary directory.
2. Run full secret scanning over the entire git history.
3. Run content searches over the entire git history for risky sales/private/employer terms.
4. Use git-filter-repo if needed to remove sensitive paths or strings.
5. Do not push rewritten history directly to public main.
6. Prepare a separate branch or separate sanitized archive for review.

Do not prioritize history recovery over getting the clean public proof-of-work repo live.

Step 10: Final audit before publishing/pushing

Before pushing the branch, run:

git status
git diff --stat
git diff --cached --stat

Search again in the public repo:

grep -RniE "api[_-]?key|token|secret|sk-|OPENAI|\.env|credential|password" .
grep -RniE "Stryker|Stanford|VA Palo Alto|hospital|patient|HIPAA|clinical decision|diagnostic|regulated|IFU" .
grep -RniE "buyer|partner|design partner|sales|sell|selling|pricing|license|licensing|commercial|enterprise|SDK handoff|acquisition|founder-led" .

If any matches remain, review them manually.

Allowed remaining terms:
- "commercial" only if saying "not a commercial product"
- "clinical" only if saying "not for clinical use"
- "regulated" only if saying "not for regulated use"
- "SDK" only if accurately describing code structure, not making buyer claims

Step 11: Push branch and prepare PR

Push the branch:

git push origin public-engine-refresh

Open a PR into main titled:

"Refresh OpenIntelligence as public document intelligence prototype"

PR description:

This refresh brings the current OpenIntelligence engineering work back into the public repo while removing private sales/productization framing.

The repo is now positioned as an experimental Apple-native document intelligence prototype focused on:
- local-first document workflows
- user-controlled files
- ingestion and retrieval
- source-backed answers
- citations
- confidence and warning signals
- library/workspace isolation
- Swift/SwiftUI implementation

This is not positioned as:
- a finished enterprise SDK
- a production commercial product
- a regulated healthcare tool
- a clinical decision-support system
- a buyer-ready handoff

Before merging, confirm:
- no secrets
- no private credentials
- no employer or hospital references
- no patient data
- no sales docs
- no pricing docs
- no buyer packet artifacts
- README is clean and public-facing
- app builds or known build limitations are documented

Step 12: Final output

When finished, report back with:

1. Files copied
2. Files intentionally excluded
3. Files rewritten
4. Risky phrases removed
5. Any remaining risky phrases
6. Build status
7. Secret scan status
8. Public-readiness recommendation:
   - Ready to merge
   - Needs cleanup
   - Do not publish yet

Important:
The goal is not to make the repo look smaller.
The goal is to make it honest.

Keep the engineering depth.
Remove the sales costume.
