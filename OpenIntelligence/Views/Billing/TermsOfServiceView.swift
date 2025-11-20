import SwiftUI

/// Display Terms of Service inline for App Review compliance.
struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Terms of Service")
                        .font(.largeTitle.weight(.bold))
                        .padding(.bottom, 8)
                    
                    Text("Last updated: November 15, 2025")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                    
                    Group {
                        section(title: "1. Acceptance of Terms", content: """
By accessing or using OpenIntelligence ("the App"), you agree to be bound by these Terms of Service. If you do not agree, do not use the App.
""")
                        
                        section(title: "2. Service Description", content: """
OpenIntelligence provides privacy-first document retrieval and AI-powered question answering. The App processes your documents locally whenever possible, with optional cloud processing via Apple Private Cloud Compute or other providers you explicitly authorize.
""")
                        
                        section(title: "3. Subscriptions & Billing", content: """
• **Free Tier**: 10 documents, 1 library
• **Starter**: $2.99/month or $24.99/year - 40 documents, 3 libraries
• **Pro**: $8.99/month or $89.99/year - Unlimited documents and libraries
• **Lifetime**: One-time $59.99 - Unlimited on-device usage
• **Document Packs**: $4.99 consumable - Adds 25 documents (max 3 active packs)

All subscriptions auto-renew unless cancelled 24 hours before renewal. Manage subscriptions in App Store settings. Cancellation stops future billing but maintains access through the current period.
""")
                        
                        section(title: "4. Privacy & Data Processing", content: """
• Documents are processed on-device by default
• Cloud processing requires explicit consent for each provider
• We do not sell or share your personal data with third parties
• See Privacy Policy for detailed data handling practices
• You retain all rights to your uploaded documents
""")
                        
                        section(title: "5. Refunds", content: """
Refunds are handled by Apple per their standard policies. Request refunds through App Store support within the applicable refund window. Consumable purchases (Document Packs) are non-refundable once used.
""")
                        
                        section(title: "6. Acceptable Use", content: """
You agree not to:
• Upload illegal or infringing content
• Attempt to reverse engineer the App
• Share account credentials
• Use the App to violate any applicable laws
• Overload or disrupt the service infrastructure
""")
                        
                        section(title: "7. Intellectual Property", content: """
OpenIntelligence and its content are owned by the developer. You retain ownership of your uploaded documents. By using the App, you grant us a limited license to process your documents solely to provide the service.
""")
                        
                        section(title: "8. Disclaimer of Warranties", content: """
THE APP IS PROVIDED "AS IS" WITHOUT WARRANTIES OF ANY KIND. We do not guarantee that the App will be error-free, secure, or always available. AI-generated responses may contain inaccuracies.
""")
                        
                        section(title: "9. Limitation of Liability", content: """
To the maximum extent permitted by law, we shall not be liable for any indirect, incidental, special, or consequential damages arising from your use of the App.
""")
                        
                        section(title: "10. Changes to Terms", content: """
We reserve the right to modify these Terms at any time. Continued use after changes constitutes acceptance. Major changes will be announced within the App.
""")
                        
                        section(title: "11. Governing Law", content: """
These Terms are governed by the laws of the United States. Disputes shall be resolved in the courts of the jurisdiction where the developer resides.
""")
                        
                        section(title: "12. Contact", content: """
For questions about these Terms, please contact us:
• Email: Gunnarguy@me.com
• Website: https://openintelligence.ai
""")
                    }
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close terms of service")
                }
            }
            .task {
                TelemetryCenter.emitBillingEvent("Terms viewed")
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
