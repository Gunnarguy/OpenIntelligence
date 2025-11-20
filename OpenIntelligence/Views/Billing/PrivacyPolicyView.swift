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
                    
                    Text("Last updated: November 15, 2025")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                    
                    Group {
                        section(title: "Our Privacy Commitment", content: """
OpenIntelligence is designed privacy-first. Your documents stay on your device whenever possible. When cloud processing is needed, we use end-to-end encrypted channels and never store your raw documents on our servers.
""")
                        
                        section(title: "Information We Collect", content: """
**On-Device Processing:**
• Document content and embeddings stored locally in app sandbox
• Usage telemetry (feature usage, performance metrics) - anonymous and aggregated
• No data leaves your device unless you explicitly authorize cloud providers

**Cloud Processing (With Your Consent):**
• Apple Private Cloud Compute: Encrypted query context, no persistent storage
• OpenAI API: Query text and document chunks (only when explicitly enabled in Settings)
• Telemetry: Cloud transmission logs (hashed, no raw document text)

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
• Store raw document text on remote servers
""")
                        
                        section(title: "Data Storage & Security", content: """
• **Local Storage**: Documents and embeddings encrypted at rest using iOS Keychain
• **Cloud Providers**: Apple PCC uses confidential computing enclaves; OpenAI API uses TLS 1.3
• **Retention**: Local data persists until you delete it; cloud providers do not retain data after processing
• **Backups**: iCloud backups may include local app data if enabled in device settings
""")
                        
                        section(title: "Your Privacy Controls", content: """
• **Consent Prompts**: Every cloud provider requires explicit authorization before first use
• **Data Deletion**: Delete documents, containers, or entire workspace in Settings
• **Telemetry**: Opt out of anonymous telemetry in Settings → Developer
• **Cloud Access**: Revoke cloud provider consent anytime in Settings → Privacy
""")
                        
                        section(title: "Third-Party Services", content: """
When you enable cloud providers:
• **Apple Private Cloud Compute**: Governed by Apple's privacy policies
• **OpenAI**: Governed by OpenAI's terms (see https://openai.com/policies/privacy-policy)

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
