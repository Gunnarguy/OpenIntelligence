import Combine
import SwiftUI

/// Display Privacy Policy inline for App Review compliance.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Privacy Policy")
                        .font(.largeTitle.weight(.bold))
                        .padding(.bottom, 8)

                    Text("Last updated: May 13, 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    Group {
                        section(title: "Our Privacy Commitment", content: """
OpenIntelligence is designed privacy-first. Your documents stay on your device by default. If you explicitly enable Shared Workspace Sync, the app copies your workspace into your iCloud Drive container so your own devices can share the same imported files and processed libraries. If Apple-managed platform processing or another provider you explicitly enable is used, OpenIntelligence does not store your raw documents on any developer-operated server.
""")

                        section(title: "Information We Collect", content: """
**On-Device Processing (Default):**
• Document content and embeddings stored locally in app sandbox
• Usage telemetry (feature usage, performance metrics) - stays on-device only
• No data leaves your device for developer-operated processing unless you explicitly enable an external provider path

**Shared Workspace Sync (Optional):**
• Imported source files, processed libraries, and chat history can be stored in your iCloud Drive app container when you enable Shared Workspace Sync
• This sync path is Apple-managed and intended only for sharing your workspace across your own devices signed into the same Apple account
• OpenIntelligence does not copy this synced workspace to any developer-operated server

**Cloud Processing (With Your Consent or Platform Routing):**
• Apple-managed platform processing, where available, is governed by Apple's privacy and security policies
• Explicitly enabled provider paths are governed by the provider's terms and privacy policies
• All telemetry and diagnostics remain entirely on-device

**Billing Data:**
• Subscription tier and status (processed by Apple, not visible to us)
• Purchase receipts validated via StoreKit (Apple-managed)
""")

                        section(title: "How We Use Your Information", content: """
• **Document Processing**: Generate embeddings, perform retrieval, answer questions
• **Service Improvement**: Analyze aggregated usage patterns to improve performance
• **Billing**: Validate subscription entitlements via App Store
• **Support**: Assist with technical issues when you contact us

We never:
• Sell your data to third parties
• Use your documents to train AI models
• Share identifiable information without consent
• Store raw document text on developer-operated remote servers
""")

                        section(title: "Data Storage & Security", content: """
• **Local Storage**: Documents and embeddings are stored in the app sandbox and protected by platform data protection
• **Optional iCloud Sync**: When Shared Workspace Sync is enabled, the app stores synced workspace data in your iCloud Drive container so another device can reuse the same imported and processed files
• **Cloud Providers**: Any enabled provider path is governed by that provider's privacy and security policies
• **Retention**: Local data persists until you delete it; provider retention is governed by the relevant provider policy
• **Backups**: iCloud backups may include local app data if enabled in device settings
""")

                        section(title: "Your Privacy Controls", content: """
• **Consent Prompts**: Every cloud provider requires explicit authorization before first use
• **Data Deletion**: Delete documents, containers, or entire workspace in Settings
• **Telemetry**: Opt out of anonymous telemetry in Settings → Developer
• **Cloud Access**: Revoke cloud provider consent anytime in Settings → Privacy
• **Workspace Sync**: Turn Shared Workspace Sync on or off anytime in Settings → Shared Workspace Sync
""")

                        section(title: "Third-Party Services", content: """
When you enable provider paths:
• **Apple-managed services**: Governed by Apple's privacy policies
• **Explicitly enabled third-party providers**: Governed by their own terms and privacy policies

We do not control third-party practices. Review their policies before enabling.
""")

                        section(title: "Children's Privacy", content: """
OpenIntelligence is not directed to children under 13. We do not knowingly collect data from children. If we learn we have collected information from a child under 13, we will delete it promptly.
""")

                        section(title: "International Users", content: """
Your data may be processed in the United States or other jurisdictions where our service providers operate. By using the App, you consent to this transfer.
""")

                        section(title: "Changes to This Policy", content: """
We may update this Privacy Policy as laws or practices change. Significant updates will be announced within the App. Continued use after changes constitutes acceptance.
""")

                        section(title: "Your Rights", content: """
Depending on your jurisdiction, you may have rights to:
• Access your personal data
• Correct inaccuracies
• Request deletion
• Object to processing
• Port your data to another service

Contact us at Gunnarguy@me.com to exercise these rights.
""")

                        section(title: "Contact Us", content: """
For privacy questions or data requests:

• Email: Gunnarguy@me.com
• Support: Tap "Contact Support" in Settings
""")
                    }
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close privacy policy")
                }
            }
            .task {
                TelemetryCenter.emitBillingEvent("Privacy policy viewed")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func section(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            Text(content)
                .font(.body)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
    }
}

#Preview {
    PrivacyPolicyView()
}
