# Phased Architecture Atlas Workflow

This playbook defines the step-by-step process for mapping the OpenIntelligence repository (Phases 0 through 9).

## Phase 0: Master Operating Rules
- **Purpose**: Establish rules and guidelines.
- **Recommended Model**: Gemini 3.1 Pro
- **Stop Condition**: User confirms rules are understood.

## Phase 1: Repository Inventory
- **Purpose**: Create a full baseline inventory of all files.
- **Recommended Model**: Gemini 3.5 Flash
- **Allowed Files**: `Docs/AuditArtifacts/ArchitectureAtlas/*_inventory.csv`, `phase_1_inventory_summary.md`
- **Forbidden Files**: App source, tests, configurations, existing docs.
- **Required Checks**: Ensure no Swift files are skipped.
- **Stop Condition**: `phase_1_inventory_summary.md` generated.

## Phase 2: System Boundary Audit
- **Purpose**: Identify high-risk integrations (PCC, StoreKit, iCloud).
- **Recommended Model**: Gemini 3.5 Flash
- **Allowed Files**: `Docs/AuditArtifacts/ArchitectureAtlas/system_boundaries.csv`, `phase_2_boundaries_summary.md`
- **Forbidden Files**: App source, tests, configurations, existing docs.
- **Required Checks**: Verify exact framework imports.
- **Stop Condition**: `phase_2_boundaries_summary.md` generated.

## Phase 3: Component Atlas
- **Purpose**: Group files into the 30 defined subsystems.
- **Recommended Model**: Gemini 3.1 Pro (for review)
- **Allowed Files**: `component_inventory.csv`, `subsystem_map.md`, `phase_3_component_summary.md`
- **Forbidden Files**: App source, tests, configurations, existing docs.
- **Required Checks**: Verify all 270+ components are mapped.
- **Stop Condition**: `phase_3_component_summary.md` generated.

## Phase 4: Call Relationships & Side Channels
- **Purpose**: Map execution flows and side channels (UserDefaults, Notifications).
- **Recommended Model**: Gemini 3.1 Pro
- **Allowed Files**: `call_relationships.csv`, `notification_and_side_channel_map.csv`, `phase_4_relationship_summary.md`
- **Forbidden Files**: App source, tests, configurations, existing docs.
- **Required Checks**: Verify exact symbols using `00_SUPERSEDING_EVIDENCE_PROTOCOL.md`.
- **Stop Condition**: `phase_4_relationship_summary.md` generated.

## Phase 5: Data-Flow and Touchpoint Map
- **Purpose**: Map data objects, cloud sync behaviors, and risk boundaries.
- **Recommended Model**: Gemini 3.1 Pro
- **Allowed Files**: `data_flow_map.csv`, `storage_touchpoints.csv`, `sync_touchpoints.csv`, `routing_touchpoints.csv`, `billing_touchpoints.csv`, `app_intents_touchpoints.csv`, `phase_5_flow_summary.md`
- **Forbidden Files**: App source, tests, configurations, existing docs.
- **Stop Condition**: `phase_5_flow_summary.md` generated.

## Phase 6: Documentation Scan & Pro Review
- **Purpose**: Map documentation deficiencies and verify claims.
- **Recommended Model**: Gemini 3.5 Flash / Gemini 3.1 Pro
- **Allowed Files**: `documentation_cross_reference.csv`, `document_claim_matrix.csv`, `document_contradictions.csv`, `phase_6_docs_summary.md`, `phase_6a_flash_scan_notes.md`, `phase_6b_pro_review.md`
- **Forbidden Files**: App source, tests, configurations.
- **Stop Condition**: `phase_6b_pro_review.md` generated.

## Phase 7: Evidence Threads Placement
- **Purpose**: Determine isolated storage boundaries for new feature.
- **Recommended Model**: Gemini 3.1 Pro
- **Allowed Files**: `evidence_threads_impact_map.csv`, `evidence_threads_design_decision.md`, `phase_7_evidence_threads_summary.md`
- **Forbidden Files**: App source, tests, configurations.
- **Stop Condition**: `phase_7_evidence_threads_summary.md` generated.

## Phase 8: Canonical Control System
- **Purpose**: Synthesize recovered maps into canonical control documents.
- **Recommended Model**: Gemini 3.1 Pro
- **Allowed Files**: `OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`, `CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`, `DOCUMENTATION_CONSISTENCY_AUDIT.md`
- **Forbidden Files**: App source, tests, configurations.
- **Stop Condition**: `phase_8_final_summary.md` generated.

## Phase 9A: Document Disposition
- **Purpose**: Classify all documentation into actionable dispositions.
- **Recommended Model**: Gemini 3.5 Flash
- **Allowed Files**: `document_disposition_matrix.csv`, `phase_9a_disposition_summary.md`
- **Forbidden Files**: App source, tests, configurations.
- **Stop Condition**: `phase_9a_disposition_summary.md` generated.

## Phase 9B: Document Correction
- **Purpose**: Execute documentation updates based on disposition matrix.
- **Recommended Model**: Gemini 3.1 Pro
- **Allowed Files**: Any target documentation file listed in the disposition matrix.
- **Forbidden Files**: App source, tests, configurations.
- **Stop Condition**: `phase_9b_docs_cleanup_summary.md` and `phase_9b_pro_review.md` generated.

## Final Comprehensive Review
- **Purpose**: Final verification gate before implementation.
- **Recommended Model**: Gemini 3.1 Pro
- **Allowed Files**: `final_readiness_matrix.csv`, `final_unresolved_risks.csv`, `final_implementation_gate.md`
- **Forbidden Files**: App source, tests, configurations.
- **Stop Condition**: `final_implementation_gate.md` states whether implementation is READY or BLOCKED.
