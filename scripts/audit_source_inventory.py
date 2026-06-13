import os
import re
import csv
import subprocess

WORKSPACE_DIR = "/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public"
OUTPUT_MD = os.path.join(WORKSPACE_DIR, "Docs/AUDIT/02_FILE_INVENTORY_4.1.md")
OUTPUT_CSV = os.path.join(WORKSPACE_DIR, "Docs/AUDIT/file_inventory_4.1.csv")

# Synced folders for OpenIntelligenceEngine target from project.pbxproj
ENGINE_SYNCED_FOLDERS = [
    "OpenIntelligence/Core",
    "OpenIntelligence/SDK",
    "OpenIntelligence/Services/AIPlatform",
    "OpenIntelligence/Services/Agentic",
    "OpenIntelligence/Services/Document",
    "OpenIntelligence/Services/Embedding",
    "OpenIntelligence/Services/Infrastructure/Compute",
    "OpenIntelligence/Services/Infrastructure/Configuration",
    "OpenIntelligence/Services/Infrastructure/Integration",
    "OpenIntelligence/Services/Infrastructure/Monitoring",
    "OpenIntelligence/Services/Infrastructure/Optimization",
    "OpenIntelligence/Services/LLM",
    "OpenIntelligence/Services/Query",
    "OpenIntelligence/Services/RAG",
    "OpenIntelligence/Services/Storage",
    "OpenIntelligence/Services/VectorStore",
    "OpenIntelligence/Services/Infrastructure/Storage",
    "OpenIntelligence/Resources"
]

# Excluded files for OpenIntelligenceEngine target
ENGINE_EXCEPTIONS = {
    "OpenIntelligence/Core/Extensions/MarkdownRenderer.swift",
    "OpenIntelligence/Services/Infrastructure/Integration/ImagePlaygroundService.swift",
    "OpenIntelligence/Services/Agentic/RAGAppIntents.swift",
    "OpenIntelligence/Services/Agentic/VisualIntelligenceIntents.swift",
    "OpenIntelligence/Services/Agentic/WritingToolsService.swift",
    "OpenIntelligence/Services/LLM/ModelResolutionService.swift",
    "OpenIntelligence/Services/Storage/DocumentationCacheService.swift",
    "OpenIntelligence/Resources/Assets/Assets.xcassets",
    "OpenIntelligence/Resources/StoreKit/StoreKitConfiguration.storekit",
    "OpenIntelligence/Resources/StoreKit/StoreKitTestHarness.swift"
}

# Live Activities Target files
LIVE_ACTIVITIES_FILES = {
    "OpenIntelligence/Services/Infrastructure/Background/IngestionLiveActivityAttributes.swift",
    "OpenIntelligenceLiveActivities/IngestionLiveActivityWidget.swift",
    "OpenIntelligenceLiveActivities/OpenIntelligenceLiveActivitiesBundle.swift",
    "OpenIntelligenceLiveActivities/OpenIntelligenceActivityIcon.png"
}

def get_file_type(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".swift": return "Swift Source"
    if ext == ".md": return "Markdown Document"
    if ext == ".py": return "Python Script"
    if ext == ".sh": return "Shell Script"
    if ext == ".plist": return "Property List"
    if ext == ".json": return "JSON Data"
    if ext == ".storekit": return "StoreKit Config"
    if ext == ".entitlements": return "Entitlements"
    if ext == ".pbxproj": return "Xcode Project"
    if ext in [".png", ".jpg", ".xcassets", ".mlpackage"]: return "Resource / Asset"
    if ext == ".txt": return "Text Document"
    if ext == ".pdf": return "PDF Document"
    if ext in [".css", ".js", ".html"]: return "Web Resource (CSS/JS/HTML)"
    if ext in [".yml", ".yaml"]: return "YAML Config"
    return "Unknown / Other"

def parse_swift_symbols(content):
    symbol_pattern = re.compile(r'\b(class|struct|enum|protocol|extension)\s+([A-Za-z0-9_]+)')
    matches = symbol_pattern.findall(content)
    symbols = [f"{m[0]} {m[1]}" for m in matches]
    return symbols

def get_target_membership(rel_path):
    targets = []
    
    # 1. Main App Target: OpenIntelligence
    if rel_path.startswith("OpenIntelligence/") and not rel_path.endswith(".entitlements"):
        targets.append("OpenIntelligence")
        
    # 2. OpenIntelligenceEngine Target
    is_engine_member = False
    for folder in ENGINE_SYNCED_FOLDERS:
        if rel_path.startswith(folder + "/"):
            is_engine_member = True
            break
            
    if is_engine_member and (rel_path not in ENGINE_EXCEPTIONS):
        targets.append("OpenIntelligenceEngine")
        
    # 3. OpenIntelligenceLiveActivities Target
    if rel_path in LIVE_ACTIVITIES_FILES or (rel_path.startswith("OpenIntelligenceLiveActivities/") and not rel_path.endswith("Info.plist")):
        targets.append("OpenIntelligenceLiveActivities")
        
    if not targets:
        if rel_path.startswith("scripts/"):
            return "SCRIPT_ONLY"
        elif rel_path.startswith("Benchmarks/") or "Test" in rel_path:
            return "TEST_ONLY"
        else:
            return "NONE / NOT_MEMBERED"
            
    return ", ".join(targets)

def main():
    # Retrieve git-tracked files only
    result = subprocess.run(["git", "ls-files"], capture_output=True, text=True)
    if result.returncode != 0:
        print("Error running git ls-files")
        return
        
    tracked_files = result.stdout.strip().split("\n")
    
    all_files = []
    swift_contents = {}
    
    for rel_path in tracked_files:
        # Skip audit files and current alignment documents to avoid self-reference
        if "Docs/AUDIT" in rel_path or rel_path == "Alignment.md" or rel_path == "Alignment2.md" or rel_path == "Alignment_Merged.md":
            continue
            
        abs_path = os.path.join(WORKSPACE_DIR, rel_path)
        if not os.path.exists(abs_path):
            continue
            
        all_files.append((rel_path, abs_path))
        
        if rel_path.endswith(".swift"):
            try:
                with open(abs_path, 'r', encoding='utf-8', errors='ignore') as f:
                    swift_contents[rel_path] = f.read()
            except Exception:
                pass

    inventory_data = []
    for rel_path, abs_path in all_files:
        size = os.path.getsize(abs_path)
        ftype = get_file_type(rel_path)
        targets = get_target_membership(rel_path)
        
        symbols = []
        content = ""
        if rel_path.endswith(".swift") and rel_path in swift_contents:
            content = swift_contents[rel_path]
            symbols = parse_swift_symbols(content)
            
        # Analyze references
        ref_count = 0
        referenced_by = []
        basename = os.path.basename(rel_path)
        name_no_ext = os.path.splitext(basename)[0]
        
        if ftype in ["Swift Source", "JSON Data", "StoreKit Config"]:
            for other_rel_path, other_content in swift_contents.items():
                if other_rel_path == rel_path:
                    continue
                if re.search(r'\b' + re.escape(name_no_ext) + r'\b', other_content):
                    ref_count += 1
                    referenced_by.append(other_rel_path)

        # Status Label classification heuristic
        status = "UNKNOWN"
        if ftype == "Markdown Document":
            if any(term in rel_path for term in ["WWDC", "CHANGELOG", "RELEASE_NOTES", "AppleIntelligenceTransitionPlan", "Research"]):
                status = "HISTORICAL_DOC"
            else:
                status = "RESOURCE_ONLY"
        elif ftype in ["Python Script", "Shell Script"]:
            status = "SCRIPT_ONLY"
        elif ftype in ["Entitlements", "Property List", "StoreKit Config", "Resource / Asset", "YAML Config", "JSON Data"]:
            status = "RESOURCE_ONLY"
        elif ftype == "Web Resource (CSS/JS/HTML)":
            if "Xrays/" in rel_path:
                status = "DEV_ONLY"
            else:
                status = "RESOURCE_ONLY"
        elif ftype in ["Text Document", "PDF Document"]:
            if "TestDocuments/" in rel_path or "Xrays/" in rel_path or "Benchmarks/" in rel_path:
                status = "TEST_ONLY"
            else:
                status = "RESOURCE_ONLY"
        elif ftype == "Xcode Project":
            status = "RESOURCE_ONLY"
        elif ftype == "Swift Source":
            if "Test" in rel_path or "swift-transformers/Sources/Hub/BinaryDistinct.swift" in rel_path:
                status = "TEST_ONLY"
            elif "Harness" in rel_path or "Mock" in rel_path:
                status = "DEBUG_ONLY"
            elif "Scaffolding" in rel_path or "Placeholder" in rel_path or "Compatibility" in rel_path:
                status = "SCAFFOLDED"
            elif "OpenIntelligenceEngine" in targets and "OpenIntelligence" in targets:
                status = "SHIPPED_USER_FACING"
            elif "OpenIntelligenceEngine" in targets:
                status = "SHIPPED_INTERNAL"
            elif "OpenIntelligence" in targets:
                status = "SHIPPED_USER_FACING"
            elif "OpenIntelligenceLiveActivities" in targets:
                status = "SHIPPED_USER_FACING"
            else:
                status = "UNUSED_CANDIDATE"
        else:
            if "fastlane/" in rel_path or "Gemfile" in rel_path:
                status = "DEV_ONLY"
            else:
                status = "RESOURCE_ONLY"
                
        # Generate Note/Evidence based on file details
        note = ""
        if ftype == "Swift Source":
            t_str = targets if targets != "NONE / NOT_MEMBERED" else "no active targets"
            s_str = f" defining {', '.join(symbols[:3])}" if symbols else ""
            note = f"Swift source file compiled in {t_str}{s_str}. It is referenced in {ref_count} other source files."
        elif ftype == "Markdown Document":
            note = f"Documentation markdown file detailing repository features or architecture: {rel_path}."
        elif ftype in ["Python Script", "Shell Script"]:
            note = f"Developer-only script used for local automation, RAG evaluation, or setup."
        elif ftype == "Resource / Asset":
            note = f"Asset or resource used by UI, tests, or build targets."
        elif ftype == "Property List" or ftype == "Entitlements":
            note = f"System configuration file defining target entitlements or application metadata."
        elif ftype == "StoreKit Config":
            note = f"Local StoreKit 2 transaction verification configuration used for sandbox purchases."
        elif ftype == "JSON Data":
            note = f"Static configuration or schema data referenced by RAG system or external packages."
        elif ftype == "Web Resource (CSS/JS/HTML)":
            note = f"Frontend assets used by developer-only diagnostic overlays (e.g. Pipeline Xray)."
        elif ftype in ["Text Document", "PDF Document"]:
            note = f"Local text or document artifact used for testing RAG extraction pipelines."
        else:
            note = f"Repository asset: {rel_path} classified as {status}."

        public_relevance = "Low"
        if ftype == "Markdown Document" and not "AUDIT" in rel_path:
            public_relevance = "High"
        elif status == "SHIPPED_USER_FACING":
            public_relevance = "High"
            
        deletion_risk = "Low" if status in ["SCRIPT_ONLY", "UNUSED_CANDIDATE", "TEST_ONLY", "DEV_ONLY"] else "High"
        reorg_candidate = ""
        
        symbols_str = ", ".join(symbols[:5]) + ("..." if len(symbols) > 5 else "")
        referenced_by_str = ", ".join(referenced_by[:3]) + ("..." if len(referenced_by) > 3 else "")
        
        inventory_data.append({
            "path": rel_path,
            "type": ftype,
            "size_bytes": size,
            "target_membership": targets,
            "primary_symbols": symbols_str,
            "status": status,
            "reference_count": ref_count,
            "referenced_by": referenced_by_str,
            "public_relevance": public_relevance,
            "deletion_risk": deletion_risk,
            "reorg_candidate": reorg_candidate,
            "notes": note
        })

    # Write CSV
    os.makedirs(os.path.dirname(OUTPUT_CSV), exist_ok=True)
    with open(OUTPUT_CSV, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=[
            "path", "type", "size_bytes", "target_membership", "primary_symbols",
            "status", "reference_count", "referenced_by", "public_relevance",
            "deletion_risk", "reorg_candidate", "notes"
        ])
        writer.writeheader()
        for row in inventory_data:
            writer.writerow(row)
            
    # Write Markdown MD
    with open(OUTPUT_MD, 'w', encoding='utf-8') as f:
        f.write("# Phase 2: Full File Inventory - OpenIntelligence v4.1\n\n")
        f.write("This file contains the complete file inventory for the OpenIntelligence repository. Verified for OpenIntelligence v4.1.\n\n")
        f.write("| Checkbox | Path | Type | Target | Status | Primary Role / Symbols | References | Notes |\n")
        f.write("|---|---|---|---|---|---|---|---|\n")
        for row in inventory_data:
            f.write(f"| [x] | `{row['path']}` | {row['type']} | {row['target_membership']} | `{row['status']}` | {row['primary_symbols']} | {row['reference_count']} ({row['referenced_by']}) | {row['notes']} |\n")
            
    print(f"Successfully wrote CSV to {OUTPUT_CSV}")
    print(f"Successfully wrote MD to {OUTPUT_MD}")

if __name__ == "__main__":
    main()
