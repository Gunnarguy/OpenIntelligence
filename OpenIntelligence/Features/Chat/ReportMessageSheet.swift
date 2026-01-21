import Foundation
import SwiftUI

/// High-level reason categories for reporting a generated response.
///
/// Keep labels user-facing and broad; downstream triage can be more detailed.
enum ReportReason: String, CaseIterable, Identifiable {
    case hateOrHarassment = "Hate or harassment"
    case sexualContent = "Sexual content"
    case violenceOrThreats = "Violence or threats"
    case selfHarm = "Self-harm"
    case privacyOrPersonalData = "Privacy / personal data"
    case misinformation = "Misinformation"
    case illegalContent = "Illegal content"
    case other = "Other"

    var id: String { rawValue }
}

/// Lightweight report UI for a single assistant message.
///
/// This doesn't transmit anything automatically; instead it prepares a report payload
/// (also copied to clipboard) and presents a share sheet so the user can send it.
struct ReportMessageSheet: View {
    let message: ChatMessage
    let onSubmit: (_ reason: ReportReason, _ notes: String, _ shouldHide: Bool, _ includeDebugContext: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason = .misinformation
    @State private var notes: String = ""
    @State private var shouldHide: Bool = true
    @State private var includeDebugContext: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Help us understand what went wrong with this response. You can review and edit the report before sending it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                }

                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Report notes")
                }

                Section("Options") {
                    Toggle("Hide this response", isOn: $shouldHide)
                    Toggle("Include debug context (model + metrics)", isOn: $includeDebugContext)
                }

                Section("Preview") {
                    Text(message.content)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Report Response")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") {
                            onSubmit(reason, notes.trimmingCharacters(in: .whitespacesAndNewlines), shouldHide, includeDebugContext)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }

    static func buildReportText(
        message: ChatMessage,
        reason: ReportReason,
        notes: String,
        includeDebugContext: Bool
    ) -> String {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "OpenIntelligence"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        let timestampISO = ISO8601DateFormatter().string(from: message.timestamp)

        var lines: [String] = []
        lines.append("# \(appName) — Content Report")
        lines.append("App Version: \(version) (\(build))")
        lines.append("Message ID: \(message.id.uuidString)")
        lines.append("Timestamp: \(timestampISO)")
        lines.append("Reason: \(reason.rawValue)")

        if includeDebugContext, let meta = message.metadata {
            lines.append("Model: \(meta.modelUsed)")
            if let ttft = meta.timeToFirstToken {
                lines.append(String(format: "TTFT: %.3fs", ttft))
            }
            lines.append("Tokens: \(meta.tokensGenerated)")
            if let tps = meta.tokensPerSecond {
                lines.append(String(format: "Speed: %.1f tok/s", tps))
            }
            lines.append(String(format: "Retrieval Time: %.0fms", meta.retrievalTime * 1000))
            if let toolCalls = meta.toolCallsMade {
                lines.append("Tool Calls: \(toolCalls)")
            }
        }

        if let containerId = message.containerId {
            lines.append("Container ID: \(containerId.uuidString)")
        }

        if !notes.isEmpty {
            lines.append("")
            lines.append("## Notes")
            lines.append(notes)
        }

        lines.append("")
        lines.append("## Message")
        lines.append(message.content)

        lines.append("")
        lines.append("---")
        lines.append("Tip: This report was prepared locally on-device. You can send it via email to the developer (see Privacy Policy → Contact Us).")

        return lines.joined(separator: "\n")
    }
}
