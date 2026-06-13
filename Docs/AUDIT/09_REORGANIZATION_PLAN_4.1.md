# Phase 10: Structure & Reorganization Proposal — OpenIntelligence v4.1

> **Documentation status:** Verified for OpenIntelligence v4.1 on 2026-06-13.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.
> **Scope:** Defines the proposed folder structure and migration plan. No files will be moved without explicit approval.

This document outlines the proposed target folder reorganization plan to improve workspace maintainability and clean up nested subdirectories.

---

## 1. Current Pain Points
- **Scattering of Diagnostic Tools:** Diagnostic overlays (`Xrays/`) and testing fixtures (`Benchmarks/`) live in separate top-level root folders instead of being grouped under a single developer utility directory.
- **Mix of Core and UI Features:** Feature folders sometimes bundle non-UI services directly, making target boundaries hard to track.

---

## 2. Proposed Target Architecture

I propose organizing the repository into these five clean root categories:

```text
OpenIntelligence/
├── App/                       # Application lifecycle configurations and launch views
├── Core/                      # Shared data models and support overrides
│   ├── Models/
│   └── Support/
├── Features/                  # UI flows, views, and view models
│   ├── Chat/
│   ├── Documents/
│   ├── Settings/
│   └── Billing/
├── Services/                  # Business logic and background engines
│   ├── AIPlatform/
│   │   ├── AppleFoundationModels/
│   │   └── CoreAI/
│   ├── Document/
│   ├── Embedding/
│   ├── LLM/
│   ├── Query/
│   ├── RAG/
│   ├── Storage/
│   └── VectorStore/
├── UI/                        # Shared design system components and templates
│   ├── DesignSystem/
│   └── Components/
└── Developer/                 # Diagnostic, benchmark, and automation utilities
    ├── Diagnostics/           # Xray dashboards (formerly root Xrays/)
    ├── Benchmarks/            # Test query banks and corpora (formerly root Benchmarks/)
    └── Scripts/               # Evaluation runner and build scripts (formerly root scripts/)
```

---

## 3. Recommended Reorganization Sequence

To minimize compilation errors, I will perform this reorganization in three distinct phases:

### Pass 1: Developer Directory Consolidation (Low Risk)
- Move root `scripts/` to `Developer/Scripts/`.
- Move root `Benchmarks/` to `Developer/Benchmarks/`.
- Move root `Xrays/` to `Developer/Diagnostics/`.
*Note:* This does not affect active application target files and has zero build breakage risk.

### Pass 2: Source File Relocations (Medium Risk)
- Consolidate all shared UI views into `UI/Components/` or `Features/`.
- Relocate custom local embedding models and vocabulary resources into a dedicated `OpenIntelligence/Resources/` directory.

### Pass 3: Project Configurations (High Risk)
- Update Xcode target folders and search path configurations to match the new disk hierarchy.
- Perform a complete project clean build (`xcodebuild clean build`) to verify that the compilation is unaffected.
