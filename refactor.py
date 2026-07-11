import sys

file_path = "OpenIntelligence/Features/Documents/Components/DocumentPicker.swift"

with open(file_path, "r") as f:
    lines = f.readlines()

output_lines = []
for i, line in enumerate(lines):
    if i == 13: # let onDocumentsPicked: ([URL]) -> Void
        output_lines.append(line)
        output_lines.append("\n    static let supportedContentTypes: [UTType] = [\n")
        output_lines.extend(lines[16:66])
        output_lines.append("    ]\n\n")

        output_lines.append("    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {\n")
        output_lines.append("        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.supportedContentTypes, asCopy: true)\n")
        output_lines.append("        picker.delegate = context.coordinator\n")
        output_lines.append("        picker.allowsMultipleSelection = true  // Enable multiple file selection\n")
        output_lines.append("        return picker\n")
        output_lines.append("    }\n")
    elif i >= 14 and i <= 70:
        pass
    else:
        output_lines.append(line)

with open(file_path, "w") as f:
    f.writelines(output_lines)
