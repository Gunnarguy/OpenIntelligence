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

*(Future Phases 5-9 will be appended here as they are defined by the user).*
