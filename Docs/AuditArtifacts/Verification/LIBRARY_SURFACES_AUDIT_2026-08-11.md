# Library surfaces audit, 2026-08-11

Eight agents surveyed four library-management surfaces, each finding checked by a second agent told
to refute it rather than agree. This records the findings **not** fixed on 2026-08-11, so the work
survives the run's transcript.

`unverified` means the verifier could not reproduce the claim and flagged it instead of asserting
it. Treat those as leads. Everything else was reproduced against the cited code.

Of 65 verified findings, 21 were fixed on 2026-08-11 and 44 remain below.

`[evidence_level: agent_survey+verified, confidence: medium, evidence_source: workflow wf_8e631d0c-746, 8 agents, 431 tool uses]`

## Documents tab action bar and library chips

### MEDIUM: The destructive Library Actions menu is genuinely undiscoverable behind a 0.45s long press with no visual affordance.

PARTIALLY WRONG AS FILED. The destructive Library Actions menu is genuinely undiscoverable behind a 0.45s long press with no visual affordance. But the prior survey's supporting evidence is half incorrect: one of the two "silent no-op" screens is unreachable, and the other is not a no-op at all.

**Evidence.** Verified: .onTapGesture at 176-178 selects, .onLongPressGesture(minimumDuration: 0.45) at 179-182 opens the dialog, and nothing in the pill renders an affordance for it. CORRECTION 1: the prior survey cites VisualizationsView.swift:97 as a live screen. struct VisualizationsView (VisualizationsView.swift:18) has zero production call sites; the only references outside the file are a comment at Embedding3DView.swift:4837 and its own #Preview at 3670, and CHANGELOG.md:79 already records that struct as orphaned. Line 97 is inside its containerPicker (94-100), so it is not evidence of anything a user can hit. CHANGELOG.md:79 also records that this exact file must not be deleted, because EmbeddingSpaceView inside it is used by Atlas. CORRECTION 2: SemanticSearchView.swift:32 is reachable, but the long press there is not a no-op; see the inert-menu problem above. The prior survey's own framing ("tapping a chip opens Library Actions" in the owner's description does not match the code) still stands as evidence the gesture is not discoverable.

### MEDIUM: Both delete paths and Clear All skip documents whose containerId is nil, while the UI shows them inside the first library.

CONFIRMED, AND THE CONSEQUENCE IS SHARPER THAN FILED. Both delete paths and Clear All skip documents whose containerId is nil, while the UI shows them inside the first library. Clear All on that library also wipes their vectors through db.clear() while keeping their metadata rows, leaving documents that are listed but retrieve nothing.

**Evidence.** filteredDocuments maps nil to the first container (DocumentLibraryView.swift:79-90, not 82-89, comment at 86 reads "Legacy docs without containerId appear only in the default container"), and documentsForContainer does the same (RAGService.swift:584-593). Deletion filters strictly: `guard let containerId = document.containerId else { return false }` at DocumentLibraryView.swift:1584 and ContainerSettingsSheet.swift:739. clearAllDocuments filters on `$0.containerId == activeId` at 6928 and 6942, so nil docs are neither tombstoned nor removed from the in-memory list, contradicting the alert at 232 ("This permanently deletes every document in ... on this device"). NEW: clearAllDocuments calls `try await db.clear()` on dbForActiveContainer() at 6914-6915, which clears the whole store. removeDocument resolves a nil containerId to `containerService.containers.first?.id` (6869), so legacy chunks live in the first container's store. Clearing the first library therefore destroys their chunks and embeddings while 6942 keeps their rows. I did not trace whether SQLiteFullTextService.deleteContainer(containerId: activeId) also removes their FTS rows, so the search-index half is untraced. Because syncContainerStats goes through documentsForContainer (910-919), the chip badge on that library still counts the survivors after the wipe.

### LOW: Chip enablement is inconsistent about scope.

CONFIRMED. Chip enablement is inconsistent about scope. Correction: the wasted-work claim is right but the prior survey implied more harm than occurs.

**Evidence.** DocumentLibraryView.swift:407 (Semantic Search) and 442 (Clear All / Remove Local Copies) use `!ragService.documents.isEmpty`, while 432 (Visualize) uses `!filteredDocuments.isEmpty`. So the destructive chip is tappable on an empty library whenever any other library has documents, and running it does db.clear(), two SQLite container deletes, a Spotlight deindex and a question-bank purge for nothing. CORRECTION: it does not write stray tombstones, because docsToDelete is empty and registerDeletedDocuments leaves `changed` false (6855-6862) so nothing is written. The exception is the first library, where the nil-containerId case above applies.

### LOW: Neither scrolling row exposes that it scrolls, and neither the action chips nor the chips themselves carry any accessibility affordance.

CONFIRMED. Neither scrolling row exposes that it scrolls, and neither the action chips nor the chips themselves carry any accessibility affordance.

**Evidence.** showsIndicators: false on both rows (DocumentLibraryView.swift:394, ContainerPicker.swift:46). DocumentActionChip (1651-1683) sets no accessibilityLabel or accessibilityHint. Grepped the whole of ContainerPicker.swift for "accessibility" and got zero hits, so the pill has no label, no hint and no accessibilityAction for the long-press-only menu. DocumentLibraryView has exactly two accessibility modifiers in 1828 lines, both accessibilityElement(children: .combine) at 1032 and 1072, neither on a chip.

### UNVERIFIED: UNVERIFIED as a runtime outcome.

UNVERIFIED as a runtime outcome. The prior survey filed the detached-write race as high and "verified by code ordering only". The code facts reproduce, one step of its mechanism is wrong, and the window is wider than it described, so I cannot rate the likelihood.

**Evidence.** Verified: saveContainers encodes synchronously then writes inside Task.detached (ContainerService.swift:248-254), while loadContainers reads synchronously (196). ContentView.swift:222-226 fires on the id-and-syncMode fingerprint of containers and calls refreshSharedWorkspaceIfNeeded(forceReload: true). createNewLibrary calls setActive(newContainer.id) at 1433, which writes the new id to UserDefaults, so if the reload sees a stale list neither the in-memory id nor the saved id is present and reloadFromDisk falls through 66-74 to loaded.first, snapping selection back to the first library. CORRECTION to the mechanism: the prior survey said the reload happens "immediately after" the mutation. It does not. refreshSharedWorkspaceIfNeeded awaits workspaceSyncService.reconfigureIfNeeded() at ContentView.swift:372 before reloadFromDisk() at 381, and bails early on an active ingestion at 377-378, so there is at least one suspension point and possibly a whole sync pass in between. That makes the race less likely than filed and unordered rather than reliably losing. I did not observe it at runtime and there is no test covering it.

### UNVERIFIED: UNVERIFIED as a runtime outcome.

UNVERIFIED as a runtime outcome. The chain from the Library Actions dialog into the Delete Library alert uses the pattern this file documents as unreliable, but I cannot reproduce a swallowed alert from code alone.

**Evidence.** Verified: handleDeleteLibrary sets showingDeleteConfirmation = true synchronously (DocumentLibraryView.swift:1540-1546) from inside the dialog button at ContainerPicker.swift:212-216, and the sibling New Library chain in the same file carries an explicit workaround with the comment "Chains are often missed if triggered too fast during alert dismissal" plus a 50ms Task.sleep (1204-1213). Not verified: that the delete chain actually drops. The two chains are not identical, alert to confirmationDialog versus confirmationDialog to alert, and SwiftUI presentation coalescing behavior on iOS 26/27 is not something I can settle by reading this repository.

### UNVERIFIED: The prior survey states that on iPhone widths "the last three chips are off-screen".

UNVERIFIED. The prior survey states that on iPhone widths "the last three chips are off-screen". The overflow problem is real but the count is a guess.

**Evidence.** Verified: six chips, HStack(spacing: 12), 16pt horizontal padding, each chip 12pt horizontal padding around an 11pt bold label (DocumentLibraryView.swift:393-451, 1651-1683), inside a ScrollView with showsIndicators: false. Not verified: how many fall off a given device width. That depends on rendered text metrics at 11pt semibold plus Dynamic Type, which I did not measure and cannot measure without running the app. Report the overflow, not the number.

## Database tab library scoping

### HIGH: NEW.

NEW. getTopTermsForContainer is not a per-library equivalent of getTopTerms, so the prior proposal to swap :229 would silently change what the Vocabulary section means and load every document's text into memory.

**Evidence.** getTopTerms :2375 reads the FTS5 vocab table: `SELECT term, doc, cnt FROM documents_vocab ORDER BY cnt DESC LIMIT ?` :2382-2387, i.e. Porter-stemmed tokens with FTS5's own document and occurrence counts. getTopTermsForContainer :2415 runs `SELECT content FROM documents WHERE container_id = ?` :2420 and tokenizes in Swift :2445-2455, filtering `$0.count >= 3 && !stopwords.contains($0)` :2449 against the hardcoded list at :2433-2441, with documentFrequency from a docIndex Set :2429/:2453. Swapping would change the terms shown, the "Docs" column at :921, and the cost profile of a chart the header calls "Top 100 Terms by Frequency" :867.

### HIGH: Reusing ContainerPill for the scope strip, as the prior survey proposed, would put "Delete Library" and a storage-mode switch on a read-only stats...

NEW, DATA-DESTROYING. Reusing ContainerPill for the scope strip, as the prior survey proposed, would put "Delete Library" and a storage-mode switch on a read-only stats screen unless every optional is explicitly suppressed.

**Evidence.** ContainerPicker.swift:124 `var canDelete: Bool = true` defaults to true. A 0.45s long press :179-182 opens the confirmationDialog :184-222 containing "Make Local Only" / "Make iCloud Sync" :191-209 and `Button(role: .destructive) { onDelete?() }` labelled "Delete Library" :211-217; macCatalyst gets the same via contextMenu :223-263. The prior survey flagged only setActive at :76 and called ContainerPill "reusable if given a different onSelect".

### MEDIUM: NEW.

NEW. An all-libraries Search would return hits with no library attribution, and fixing that properly needs the hard-boundary service.

**Evidence.** FTS5SearchResult at SQLiteFullTextService.swift:26-32 carries documentId, content, bm25Score, snippet, highlightedContent and no containerId. searchSection :1306-1415 shows no library anywhere, and SearchResultRow :1410 receives only `documentName(for: result.documentId)` (:1492-1493, which falls back to a UUID prefix on a miss). Passing nil to timedSearch :1458 therefore mixes libraries invisibly. A per-row library label needs either containerId on FTS5SearchResult (hard boundary) or a view-side lookup against ragService.documents.

### MEDIUM: getDocumentStats has no all-libraries mode and no other service call can substitute.

CONFIRMED. getDocumentStats has no all-libraries mode and no other service call can substitute.

**Evidence.** SQLiteFullTextService.swift:2104 `func getDocumentStats(containerId: UUID)` with `WHERE container_id = ?` :2116, and it is the only function in the file returning [DocumentStat] (struct :2094-2101). The near miss, getDocumentLengthStats(containerId: UUID? = nil) :2609 with a genuine all-libraries branch at :2621-2625, returns DocumentLengthStat :2599-2606, which has no containerId and no createdAt and so cannot feed DocumentStatRow. The file is hard boundary, so an unfiltered variant is unavailable without the owner naming it.

### MEDIUM: Two different numbers wear the label "Unique Terms" on one screen, and the Overview one is capped at 100.

CONFIRMED. Two different numbers wear the label "Unique Terms" on one screen, and the Overview one is capped at 100.

**Evidence.** DatabaseDashboardView.swift:480-485 renders `value: "\(topTerms.count)"` with `label: "Unique Terms"`, and topTerms comes from `service.getTopTerms(limit: 100)` :229. The Index section shows `IndexStatCard(title: "Unique Terms", value: formatLargeNumber(indexInfo.uniqueTerms)...)` :773-778 from the unfiltered COUNT(DISTINCT term) at :2173. I cannot confirm the "3.1K" figure the prior survey quoted from the screenshot, but the duplicate label and the 100 cap are both in code.

### MEDIUM: Index and Vocabulary show whole-database figures with no scope label, directly beneath a control that currently reads a single library's name.

CONFIRMED. Index and Vocabulary show whole-database figures with no scope label, directly beneath a control that currently reads a single library's name.

**Evidence.** Index cards :773-799 (Unique Terms, Total Occurrences, Avg Frequency, Compression) all read indexInfo from getIndexInfo() :2163-2196, which has no container parameter and derives compression from a FileManager file size :2182-2185. The Vocabulary header "Top 100 Terms by Frequency" :867 is fed by the global getTopTerms :229. Neither carries scopeSubtitle, unlike the Overview cards at :426, :435 and :444.

### MEDIUM: CONFIRMED as a future risk of the proposal, not a present bug.

CONFIRMED as a future risk of the proposal, not a present bug. A scope that stores its own library UUID can go stale and would render silent zeros.

**Evidence.** ContainerService.swift:128-143 removes the container at :131 and reassigns activeContainerId at :132-134 with no notification to this view. Today :323 always re-reads activeContainerId so the case is unreachable. Once the scope carries a UUID, `stats.containerStats.first { $0.containerId == id }?.documentCount ?? 0` :328 returns 0 for a library that no longer exists, and containerName(for:) :1488-1490 would render "Unknown".

### LOW: NEW.

NEW. Dead code in the area that the prior survey either treated as live or did not see.

**Evidence.** loadStatistics() :1441-1448 has zero call sites (repo-wide grep for `loadStatistics` returns :1441 plus VisualizationsView.swift:3196/:3519/:3563, that view's own method), yet the prior survey cited its :1446 as a second live hardwiring and proposed editing it. `@State private var docLengthStats` :38 is never assigned or read anywhere. FTS5Statistics.documentsPerContainer :1967, populated at :2083, has no reader. Reporting these as observations only; per the repo's own rule, do not delete any of them on the strength of a call-site count.

### LOW: A .segmented Picker is the wrong control for five or more libraries, but the prior survey's supporting evidence is wrong.

PARTLY CONFIRMED. A .segmented Picker is the wrong control for five or more libraries, but the prior survey's supporting evidence is wrong.

**Evidence.** `.pickerStyle(.segmented)` :363 is real and segmented pickers do compress their labels. The cited corroboration is not: the section tab row at :374-403 puts `Text(section.label)` :385 in a horizontal ScrollView :375 with no lineLimit or truncationMode, so it scrolls rather than truncates. ContainerPill's `.truncationMode(.middle)` and `.minimumScaleFactor(0.9)` at :147-149 do exist and are real evidence that library names need shrink handling.

### LOW: NEW, small copy defect already shipped in this area.

NEW, small copy defect already shipped in this area. A user-visible em-dash, against the standing rule.

**Evidence.** DatabaseDashboardView.swift:675 renders `value: documentStats.isEmpty ? "-" : ...` as the Avg Words/Doc placeholder. :656 and :610 also use "•" as a separator in user-facing strings. Flagging, not proposing a change, since it predates this task.

### UNVERIFIED: Every screenshot-derived claim in the prior survey.

UNVERIFIED. Every screenshot-derived claim in the prior survey.

**Evidence.** I have no access to the screenshot. Cannot reproduce: that the visible truncated tab is Vocabulary rendered as "Ab.."; that the Index section reads 3.1K; that exactly four section tabs were visible; that the control displayed "General" (though ContainerService.swift:285 names the default library "General", which makes it plausible). None of these change the code-level findings.

### UNVERIFIED: Whether deleting a library leaves orphan document_meta rows that would inflate the all-libraries totals above the sum of the pickable libraries.

UNVERIFIED. Whether deleting a library leaves orphan document_meta rows that would inflate the all-libraries totals above the sum of the pickable libraries.

**Evidence.** The UI delete path (DocumentLibraryView.swift:1549-1609) removes each document via ragService.removeDocument :1590 before containerService.deleteContainer :1595, and a container-wide FTS delete exists (SQLiteFullTextService.swift:678, `DELETE FROM documents WHERE container_id = ?` :698 and `DELETE FROM document_meta WHERE container_id = ?` :708) called from RAGService.swift:6669 and :6923. I did not trace removeDocument (RAGService.swift:6866) to confirm it clears document_meta for every path, so I cannot say whether containerStats can contain ids absent from containerService.containers. If it can, containerName(for:) :1489 renders "Unknown" in containerBreakdownCard :607 and the all-libraries totals exceed the pickable libraries.

## Library Settings sheet

### MEDIUM: REPRODUCES, but the prior survey's own list of triggers is incomplete in the same way it criticizes.

REPRODUCES, but the prior survey's own list of triggers is incomplete in the same way it criticizes. Sections:824 ("Saving will trigger a re-embed if the embedding model or dimension changes") is wrong in four ways, not three: it prompts rather than triggers (dialog at ContainerSettingsSheet.swift:311-326 with a "Later" escape); it omits translation-language change (line 692); it omits chunking change, which shows the same dialog via needsRechunk at :693 and :702-708; and dimension cannot change from this sheet, since the only dimension picker is in the unrendered embeddingResolutionSection (Sections:980-985) and both provider options declare supportedDimensions: [384] (ContainerSettingsSheet.swift:399, 449). Note the container's dim can still change outside the sheet via Auto Intelligence (RAGService.swift:7510-7514), which is what makes the onAppear auto-correct at :239-247 reachable at all.

**Evidence.** Sections:824; ContainerSettingsSheet.swift:239-247, 311-326, 399, 449, 692-711; Sections:968-990 unrendered; RAGService.swift:7528-7568

### MEDIUM: Runtime provider availability is computed and discarded.

REPRODUCES AS CLAIMED. Runtime provider availability is computed and discarded. refreshProviderAvailability probes each option with EmbeddingService.forProvider(..., allowFallback: false).isAvailable and stores the result in providerAvailability (ContainerSettingsSheet.swift:549-575), then only logs it. Its three consumers have no call sites: isCurrentProviderAvailable (97), providerUnavailableWarning (102-127), currentProviderName (130-145). The rendered cards gate on option.isSelectable (Sections:886, 889), which is a compile-time value. On a device where the Core ML model fails to load, "Neural Engine (MiniLM)" still renders enabled with badge "✓ Default".

**Evidence.** ContainerSettingsSheet.swift:97-145, 386-405, 549-575; Sections:878-892; exhaustive grep returns only the definitions

### MEDIUM: The re-embed progress UI is unreachable.

REPRODUCES AS CLAIMED. The re-embed progress UI is unreachable. startReembedding sets isReembedding and drives reembedProgress (ContainerSettingsSheet.swift:782-804); ReembedStatusBanner (1384-) is referenced only from reembedWarnings (Sections:1076), inside embeddingResolutionContent (:989), inside the unrendered embeddingResolutionSection. During a rebuild the sheet stays open with a disabled Save (:217) and no progress, count or filename, dismissing only when reembedDocuments returns (:795).

**Evidence.** ContainerSettingsSheet.swift:217, 782-805, 1384; Sections:989, 1060-1078; grep: ReembedStatusBanner has exactly one reference

### MEDIUM: "v4.5.0" (Sections:1636) is stale: CHANGELOG.md's latest release is "## 5.0 - 2026-08-10" with "<!-- next-version: 5.1 -->".

PARTLY CORRECTED. "v4.5.0" (Sections:1636) is stale: CHANGELOG.md's latest release is "## 5.0 - 2026-08-10" with "<!-- next-version: 5.1 -->". But the prior survey's fix ("replace with the bundle's own version string") is not clean, because MARKETING_VERSION in project.pbxproj is 4.9 (:782, :847), so the app version and the changelog disagree, and the label sits on a card titled "AI Subsystem Diagnostics" where it may be intended as a subsystem version rather than an app version. Swapping in the bundle version changes what the label asserts. "Latency Profile: Microsecond Batching (<1ms)" (Sections:1740) has no measurement anywhere I could find. "Citation Alignment: Exact Byte-Level Offsets" (Sections:1731) is measurably imprecise for the offsets the pipeline actually records: SemanticChunker.swift:1451-1452 computes them with fullText.distance(from:to:), which is a Swift Character (grapheme cluster) count, not a byte count, and I found no byte-offset mechanism in the tokenizer wrapper. The two verifiable claims in the same card hold and must stay: "Rust-backed swift-tokenizers" (dependency declared at OpenIntelligence/swift-transformers/Package.swift:14 on DePasqualeOrg/swift-tokenizers; provider logs "Loaded Rust-backed tokenizer" at CoreMLSentenceEmbeddingProvider.swift:193) and "30,522 (BERT WordPiece)" (embedding_tokenizer.bundle/tokenizer.json has exactly 30,522 vocab entries, counted). Note the prior survey cited the Rust source at OpenIntelligence/swift-transformers/.build/checkouts/..., which is gitignored by OpenIntelligence/swift-transformers/.gitignore:2; cite Package.swift:14 instead.

**Evidence.** Sections:1636, 1714, 1723, 1731, 1740; CHANGELOG.md:1-5; project.pbxproj:782, 847; SemanticChunker.swift:1451-1452; CoreMLSentenceEmbeddingProvider.swift:189-197; OpenIntelligence/swift-transformers/Package.swift:14; tokenizer.json vocab count 30522

### MEDIUM: The prior survey concludes "mode alone never escalates" from FoundationModelRoutePolicy.swift:97-117.

MATERIALLY WRONG AS DIAGNOSED, THOUGH THE COPY IS STILL WRONG. The prior survey concludes "mode alone never escalates" from FoundationModelRoutePolicy.swift:97-117. That reads only the third branch of determineRoute. Two earlier branches escalate without the context exceeding the window: a manual fmPreference of .privateCloudCompute returns PCC unconditionally (:53-54), and when a ModelExecutionPlan is attached the function returns straight from plan.synthesisTarget (:35-46). The plan is the normal path; the function's own comment at :61-67 and :73-77 says the planless branch is reached only when no plan is attached. In the planner, complexityRequestsPCC = evidence.requiresMultiDocumentSynthesis && constraints.qualityMode != "Standard" and shouldUsePCC = ... && (!localBudget.fits || complexityRequestsPCC) (ModelExecutionPlanner.swift:79-85). So Deep Think or Maximum plus multi-document synthesis DOES escalate with the local budget fitting, and Sections:1520's mode clause is substantially true. What is genuinely wrong is narrower: the hardcoded 4,096 at Sections:1618 and ">4K tokens" at :1520. onDeviceLimit is FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true), which returns SystemLanguageModel.default.contextSize on iOS/macOS 26+ and only falls back to baseContextLength = 4096 (FoundationModelTokenBudget.swift:25-40), so a fixed figure is a guess about the device. Both strings also omit the conditions the code enforces: network, foreground-or-consent, the signed entitlement and PCC quota. Fix the numbers and add the conditions; do not weaken the mode clause on the prior survey's reasoning.

**Evidence.** Sections:1520, 1614-1621; FoundationModelRoutePolicy.swift:28-47, 53-54, 61-67, 71, 87-118, 121-132; FoundationModelTokenBudget.swift:25-40; ModelExecutionPlanner.swift:79-89, 119; ModelExecutionPlan.swift:191-193

### LOW: Sections:216 ("Changing it requires re-indexing existing documents") overstates the setting's reach.

REPRODUCES AS CLAIMED. Sections:216 ("Changing it requires re-indexing existing documents") overstates the setting's reach. preferredTranslationLanguage is read as a query-side target (RAGService.translationTargetLanguage:4267-4275, consumed by translatedQueryForEmbedding:4277). Its only ingestion-side consumer is the document summary chunk's embedding target (RAGService.swift:6127 -> DocumentSummaryService.swift:101, 134). Document chunk embeddings are not language-retargeted, so a full re-index is heavier than the change warrants, even though Save does prompt for one (ContainerSettingsSheet.swift:692).

**Evidence.** Sections:216; RAGService.swift:4267-4275, 4277, 6127; DocumentSummaryService.swift:101, 134; ContainerSettingsSheet.swift:692

### LOW: The prior survey says "Six em-dashes in user-facing strings" and then enumerates eight.

COUNT CORRECTED. The prior survey says "Six em-dashes in user-facing strings" and then enumerates eight. Eight is right. Rendered: Sections:43 "Semantic chunking - topic-aware splitting", :183 "AI features - per-library overrides", :868 "Embedding model - sentence → vector transformation", :713 "Hybrid retrieval - vector + BM25 fusion" (developer-gated), and ContainerSettingsSheet.swift:1175 "No documents yet-ready to profile whatever you drop in." (AutoIntelligencePanel.headline, shown when corpus.documentCount == 0). Unrendered: Sections:573, :1018, :1082. Two more are in code comments, not copy: ContainerSettingsSheet.swift:197 and :202. Separately, if a punctuation sweep runs, Sections:868 and :1836 also use U+2192 "→" inside user-visible text, which the standing rule does not cover but which reads the same way.

**Evidence.** grep for U+2014 across OpenIntelligence/Features/Documents/Settings/ returns Sections:43, 183, 573, 713, 868, 1018, 1082 and ContainerSettingsSheet.swift:197, 202, 1175

### LOW: Dead members in the sheet, each verified by exhaustive grep.

REPRODUCES AS CLAIMED. Dead members in the sheet, each verified by exhaustive grep. Never read: chunkingSource (ContainerSettingsSheet.swift:46, written only at :260 and :265; the identically named symbols in RAGService.swift:134 and RAGPipelineAuditView.swift:123 are unrelated), actualProviderInUse (:49), providerFallbackReason (:50). Never called: validateDimensionForProvider (:156-168), availableDimensionValues (:487-492), formatBytes64 (Sections:1474-1484). Never instantiated: LibraryThemePreset (:875). Reachable only from unrendered views: dimensionOptions (:462), availableDimensionOptions (:480), vectorDBOptions (:498), VectorDBOptionDescriptor (:856).

**Evidence.** ContainerSettingsSheet.swift:46, 49, 50, 156-168, 462-492, 498-522, 856, 875; Sections:1474-1484; per-symbol greps return only definitions plus the noted writes

### LOW: PARTLY CORRECTED, AND THE PRIOR SURVEY'S FIX WOULD CREATE A NEW FALSE CLAIM.

PARTLY CORRECTED, AND THE PRIOR SURVEY'S FIX WOULD CREATE A NEW FALSE CLAIM. The Deep Dive does ignore the container's persisted stat fields and cannot show on-disk size: vectorSpaceStatsCard recomputes documents and chunks from activeContainerDocuments (Sections:1262-1263) and shows an estimate labelled "Est. Vector Bytes" and "(Float32 estimate)" (:1274, :1283), never lastIndexedAt. But the naming and the fix are both wrong. There is no ContainerService.syncContainerStats; it is RAGService.syncContainerStats (RAGService.swift:910-919) calling ContainerService.updateStats (ContainerService.swift:147-188). More importantly, dbSizeBytes is NEVER written with a real value: repo-wide grep finds only the model declaration and decode-to-0 (KnowledgeContainer.swift:62, 101, 162, 183), the unused updateStats parameter (ContainerService.swift:151, 164, 183), and a max() in WorkspaceSyncService.swift:1701. No caller supplies it, and syncContainerStats passes totalDocuments, totalChunks and lastIndexedAt only. Surfacing dbSizeBytes as the prior survey proposes would render "0 B" for every library, which is a new false user-facing claim, not a fix.

**Evidence.** Sections:1255-1291, 1474-1484; KnowledgeContainer.swift:60-63, 101, 162, 183; ContainerService.swift:147-188; RAGService.swift:910-919, 6317; WorkspaceSyncService.swift:1701; repo-wide grep for dbSizeBytes

### LOW: Developer-only retrieval sliders can be overwritten by auto-tuning with no note in the copy.

REPRODUCES AND IS STRONGER THAN CLAIMED. Developer-only retrieval sliders can be overwritten by auto-tuning with no note in the copy. retrievalTuningSection sets minSimilarity, vectorWeight/lexicalWeight, mmrLambda, minConfidentChunks and requireExplicitCitations (Sections:724-806). autoTuneRetrievalConfigIfNeeded skips only when current.minSimilarity >= 0.5 or current.requireExplicitCitations (RAGService.swift:7435-7441); otherwise, if the recommended weights or minSimilarity differ, it assigns the WHOLE config: updatedContainer.retrievalConfig = recommended (:7449). So mmrLambda and minConfidentChunks are also discarded, not just the three compared fields. The slider range is 0.15...0.70 (Sections:736), so the escape hatch is reachable but undocumented.

**Evidence.** Sections:712-808, 736; RAGService.swift:7418-7455; KnowledgeContainer.swift:313-381

### UNVERIFIED: UNVERIFIED, flagged rather than asserted.

UNVERIFIED, flagged rather than asserted. "Latency Profile: Microsecond Batching (<1ms)" (Sections:1740): I found no measurement, benchmark or mechanism backing a sub-millisecond figure in this repo, but I did not exhaustively search the embedding batch path, and absence of a figure in the files I read is not proof the claim was never measured. Run oi-claim-audit before touching it. Same status for the "40%+ faster" and "40%+ latency reduction" claims on the Core AI provider option (ContainerSettingsSheet.swift:441, 458), which the prior survey did not examine at all and which are rendered whenever the Core AI card shows.

**Evidence.** Sections:1740; ContainerSettingsSheet.swift:441-458

### UNVERIFIED: Whether the sheet's write-back of container.retrievalConfig (ContainerSettingsSheet.swift:604) can clobber an auto-tune that landed while the sheet...

UNVERIFIED. Whether the sheet's write-back of container.retrievalConfig (ContainerSettingsSheet.swift:604) can clobber an auto-tune that landed while the sheet was open. onAppear loads retrievalConfig once at :248 behind hasInitialized, and the onChange at :285-289 refreshes only intelligence and provider availability, never the form fields. Auto-tune writes the container from ingestion (RAGService.swift:7451). Whether ingestion can complete while this modal sheet is up, and therefore whether the stale value is actually reachable, I did not determine.

**Evidence.** ContainerSettingsSheet.swift:220-222, 248, 285-289, 604; RAGService.swift:7418-7451

## Delete, wipe and remove semantics

### HIGH: CONFIRMED for Clear All, and understated: all three in-app delete-library paths have the same nil-containerId hole, so deleting the default library...

CONFIRMED for Clear All, and understated: all three in-app delete-library paths have the same nil-containerId hole, so deleting the default library orphans legacy documents into a library they were never in.

**Evidence.** clearAllDocuments filters and removes on $0.containerId == activeId (:6928, :6942), false for nil. The same guard appears in DocumentLibraryView.confirmDeleteLibrary (:1584), ContainerSettingsSheet.confirmDeleteLibrary (:739) and deleteConflictedLocalLibraries (:1507). Meanwhile filteredDocuments shows nil-containerId docs in the default library (:81-89), removeDocument resolves nil to containers.first (:6869), deleteContainer reassigns the default to the next container (:132-135), and a self-test asserts the rule (ContainerScopingSelfTestsView.swift:204, :267). containerId is optional at DocumentChunk.swift:440, inside struct Document which begins :430.

### MEDIUM: The claim that chat history and container vector files are "never removed" is FALSE.

CORRECTED. The claim that chat history and container vector files are "never removed" is FALSE. They are removed on the next sync pass. The real residue is narrower: it survives only when no shared workspace is active.

**Evidence.** WorkspaceSyncService.swift:1389-1397 removes the vector store artifacts (removeVectorStoreArtifacts :2563-2567) and chat_history_<id>.json / transcript_<id>.json / conversation_memory_<id>.json for every container that dropped out of the local inventory; chat_history_ matches AppSupportPaths.chatHistoryURL (KnowledgeContainer.swift:465). The prior survey's "only ever read or written (RAGService.swift:861, :931), never removed" is contradicted by that loop. Still true: deleteContainer deletes no files by design (:141-142), no delete path calls invalidateAndClearStorage, and invalidate(containerId:) (:134-136) is never called so the cached store persists. For a Local Only library with sync off or below Pro (gates at :375-390) the files do persist, and "This cannot be undone" (DocumentLibraryView.swift:291) overpromises.

### MEDIUM: The two delete-library implementations do diverge, but not for the stated reason.

CORRECTED. The two delete-library implementations do diverge, but not for the stated reason. resolvedLocalDeletionContainerIDs cannot catch merge-duplicated libraries; its fallback branch is unreachable in effect.

**Evidence.** containerDeletionMergeKey returns container.id.uuidString.lowercased() (:1634-1638), the container's own id, so the matching loop at :1626-1629 can only match a container with the identical UUID, which the early return at :1616-1618 already returned. The function yields [targetContainer.id] when present and [] when absent, behaviourally the same as ContainerSettingsSheet's hardcoded [container.id] (:731) except in the already-gone case. The real divergences: DocumentLibraryView aborts and surfaces an iCloud failure (:1565-1571) while ContainerSettingsSheet logs and continues (:726-728); and DocumentLibraryView reports a status message (:1600-1603). Both DO call cancelAndPurgeIngestion (:1579, :734), so that is not one.

### MEDIUM: CONFIRMED with a reframe.

CONFIRMED with a reframe. The wipe operation exists and is hard to find, but calling clearLibrary(id:) dead code mischaracterizes it.

**Evidence.** clearAllDocuments (:6913) is surfaced only as the last chip in a horizontally scrolling strip labelled "Clear All" or "Remove Local Copies" (DocumentLibraryView.swift:438-446). OpenIntelligenceEngine.clearLibrary (:459-466) has zero call sites, verified by whole-repo grep, but so do its siblings deleteLibrary (:416) and removeDocument(id:from:) (:445): the SDK is an unconsumed public surface, not abandoned code. clearLibrary also changes the active library as a side effect (:464). ContainerService genuinely has no clear/empty/purge/wipe function, verified by listing all eleven of its funcs.

### MEDIUM: "Delete Everywhere" reports success even when the iCloud deletion never happened.

CONFIRMED. "Delete Everywhere" reports success even when the iCloud deletion never happened.

**Evidence.** try? at DocumentCard.swift:134 discards the error. deleteDocumentFromICloud returns silently when sync is off (guard isSyncEnabled else { return }, :641) and throws user-readable messages at :650-656 and :658-664 that nothing displays. The local removal at :136 runs regardless, so the document leaves this device with its iCloud copy intact and no warning.

### MEDIUM: NEW, missed by the prior survey.

NEW, missed by the prior survey. Clear All does not cancel in-flight ingestion, so a wipe during import races the queue and the imported documents come back.

**Evidence.** Both live delete-library paths call cancelAndPurgeIngestion first (DocumentLibraryView.swift:1579, ContainerSettingsSheet.swift:734), which tombstones queue items, suppresses self-healing and cancels the active task (RAGService.swift:4659-4698). clearAllDocuments (:6913-6952) never calls it and never touches ingestionItems or the persisted queue.

### MEDIUM: NEW.

NEW. There are four delete-library implementations and two copies of the pill's destructive menu, so a label, gate or confirmation change has to land in six places to be consistent.

**Evidence.** DocumentLibraryView.confirmDeleteLibrary :1549-1610; ContainerSettingsSheet.confirmDeleteLibrary :715-761; DocumentLibraryView.deleteConflictedLocalLibraries :1494-1538; OpenIntelligenceEngine.deleteLibrary :416-426. Menus: ContainerPicker.swift:184-222 (iOS confirmationDialog) and :223-262 (macCatalyst contextMenu), which duplicate Make Local Only, Make iCloud Sync and Delete Library verbatim.

### LOW: The entity-index finding is void, and the real problem is two false claims in a doc comment.

CORRECTED. The entity-index finding is void, and the real problem is two false claims in a doc comment. Nothing populates EntityIndexService, so there is nothing for Clear All to fail to clear.

**Evidence.** indexChunk (:92) and indexChunks (:135) have zero call sites repo-wide; the only other indexChunk is a no-op Spotlight stub (EngineSDKCompatibility.swift:54-65). The header asserts "RAGService.ingestDocument() calls EntityIndexService.indexChunk()" (:31) and that AgenticOrchestrator.executeGraphExpansion() uses chunksForEntity() (:32); grep finds neither. So the prior survey's "wrong entity count in the maintenance log (BackgroundTaskService.swift:1283-1295)" is unsupportable: that log would report zero.

### LOW: CONFIRMED, and worse than stated: the chip is enabled on a visibly empty library because the empty state renders the same header.

CONFIRMED, and worse than stated: the chip is enabled on a visibly empty library because the empty state renders the same header.

**Evidence.** isEnabled: !ragService.documents.isEmpty (:442) is global while the action targets only the active container. emptyStateView (:162-181) renders documentHeader at :165, and documentHeader contains documentActionStrip at :219, so on an empty library with documents elsewhere the red "Clear All" chip is live and its alert offers to delete nothing.

### LOW: MINOR CORRECTIONS to cited ranges.

MINOR CORRECTIONS to cited ranges. None changes a conclusion, but they should not be copied forward.

**Evidence.** deleteLibrarySection is ContainerSettingsSheet+Sections.swift:1496-1513, guard :1498, button :1500-1510, and it is the 10th Form section, 11th only when settings.developerRAGTuningEnabled admits retrievalTuningSection (ContainerSettingsSheet.swift:198-200). BNNS clear() ends :672. cleanupSharedWorkspace is :2847-2870; cleanupSharedImportedDocuments :2872-2890. The persistentJSON case is VectorStoreRouter.swift:93-97. SQLiteFullTextService.delete(for:) is :629-675 with tables at :634, :644, :654, :664; deleteContainer(containerId:) begins :678; deleteChunksForContainer :992. invalidateAndClearStorage has one direct caller (RAGService.swift:3756) but is reachable from four via invalidateVectorStore :3754 (ContainerSettingsSheet.swift:660, RAGService.swift:4230, :5267, :5272); the conclusion that no delete or wipe path reaches it still holds.

### UNVERIFIED: Whether any user's data actually contains nil-containerId documents.

Whether any user's data actually contains nil-containerId documents. The code-path mismatch is verified; the population is not.

**Evidence.** Document.containerId is optional (DocumentChunk.swift:440) and three layers encode a nil-means-default rule (DocumentLibraryView.swift:81-89, RAGService.swift:6869, ContainerScopingSelfTestsView.swift:204). I inspected no on-device store and cannot say whether legacy nil rows exist in the field.

### UNVERIFIED: Whether stale entity-index entries exist on any device despite nothing populating the index in this tree.

Whether stale entity-index entries exist on any device despite nothing populating the index in this tree.

**Evidence.** EntityIndexService.loadFromDisk (:340-341) decodes a persisted snapshot, so a build that once called indexChunk could have left one behind. I did not check git history for when indexing was removed and cannot confirm or rule out on-device residue.

### UNVERIFIED: Whether the re-embed path leaks tombstones.

Whether the re-embed path leaks tombstones. RAGService.swift:7340 removes the document (writing a tombstone for the old id) then re-adds via addDocument (:7352), which presumably mints a new id, so deleted_documents.json would grow by one entry per document per rebuild.

**Evidence.** clearDeletionTombstones (:6819-6840) is called only from the already-imported skip branch (:5131), which a freshly removed document cannot reach. I did not trace addDocument far enough to confirm the new-id assumption or measure harm, so I am not asserting a defect.
