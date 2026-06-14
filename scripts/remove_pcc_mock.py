file_path = "OpenIntelligence/Core/Support/EngineSDKCompatibility.swift"
with open(file_path, "r") as f:
    lines = f.readlines()

# The mock starts at line 151 (#if canImport(FoundationModels))
# We will keep lines 0 to 150 (which is up to index 149)
new_lines = lines[:150]

with open(file_path, "w") as f:
    f.writelines(new_lines)

print("Removed PCC Mock from EngineSDKCompatibility.swift")
