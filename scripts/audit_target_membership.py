import csv
import os

WORKSPACE_DIR = "/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public"
CSV_PATH = os.path.join(WORKSPACE_DIR, "Docs/AUDIT/file_inventory_4.1.csv")
OUTPUT_PATH = os.path.join(WORKSPACE_DIR, "Docs/AUDIT/03_TARGET_MEMBERSHIP_4.1.md")

def main():
    target_map = {
        "OpenIntelligence": [],
        "OpenIntelligenceEngine": [],
        "OpenIntelligenceLiveActivities": [],
        "OpenIntelligence & OpenIntelligenceEngine": [],
        "None (Development/Scripts/Docs)": []
    }
    
    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            path = row["path"]
            targets_str = row["target_membership"]
            status = row["status"]
            
            # Skip file system artifacts like raw benchmark output files or logs to keep the target list clean and relevant
            if "BenchmarkRuns/" in path or "DerivedData/" in path:
                continue
                
            targets = [t.strip() for t in targets_str.split(",") if t.strip()]
            
            if "OpenIntelligence" in targets and "OpenIntelligenceEngine" in targets:
                target_map["OpenIntelligence & OpenIntelligenceEngine"].append((path, status))
            elif "OpenIntelligence" in targets:
                target_map["OpenIntelligence"].append((path, status))
            elif "OpenIntelligenceEngine" in targets:
                target_map["OpenIntelligenceEngine"].append((path, status))
            elif "OpenIntelligenceLiveActivities" in targets:
                target_map["OpenIntelligenceLiveActivities"].append((path, status))
            else:
                target_map["None (Development/Scripts/Docs)"].append((path, status))
                
    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        f.write("# Phase 3: Xcode Target Membership Mapping - OpenIntelligence v4.1\n\n")
        f.write("This document tracks Xcode target membership and build configuration mapping. Verified for OpenIntelligence v4.1.\n\n")
        
        f.write("## 1. Summary of Targets\n")
        f.write(f"- **OpenIntelligence (Main App Target):** {len(target_map['OpenIntelligence']) + len(target_map['OpenIntelligence & OpenIntelligenceEngine'])} files\n")
        f.write(f"- **OpenIntelligenceEngine (Engine Target):** {len(target_map['OpenIntelligenceEngine']) + len(target_map['OpenIntelligence & OpenIntelligenceEngine'])} files\n")
        f.write(f"- **OpenIntelligenceLiveActivities (Extension Target):** {len(target_map['OpenIntelligenceLiveActivities'])} files\n")
        f.write(f"- **No target (Scripts, Docs, Tests, Benchmarks):** {len(target_map['None (Development/Scripts/Docs)'])} files (excluding raw benchmark run logs)\n\n")
        
        f.write("## 2. Dynamic Target Membership Mechanics (Xcode 26)\n")
        f.write("The project utilizes Xcode 26's **FileSystemSynchronizedGroups** (Folder Sync) feature:\n")
        f.write("1. **OpenIntelligence App target** maps to the `OpenIntelligence/` directory on disk, automatically compiling all source files inside it.\n")
        f.write("2. **OpenIntelligenceEngine framework target** maps to specific synchronized groups (e.g. `Core`, `SDK`, `Services/...`, `Resources`).\n")
        f.write("3. **Exclusions** are maintained via `PBXFileSystemSynchronizedBuildFileExceptionSet` blocks in the project file, ensuring app-specific views, local LLM servers, or testing resources do not spill into the SDK target.\n\n")
        
        f.write("## 3. Detailed Target Lists\n\n")
        
        for group, files in target_map.items():
            f.write(f"### Target Group: {group}\n")
            f.write(f"Total files: {len(files)}\n\n")
            f.write("| File Path | Status | Notes |\n")
            f.write("|---|---|---|\n")
            # Sort files by path name
            sorted_files = sorted(files, key=lambda x: x[0])
            for path, status in sorted_files:
                f.write(f"| `{path}` | `{status}` | |\n")
            f.write("\n")
            
    print(f"Successfully wrote Target Membership to {OUTPUT_PATH}")

if __name__ == "__main__":
    main()
