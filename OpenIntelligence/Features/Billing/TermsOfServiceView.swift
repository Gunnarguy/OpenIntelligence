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

                    Text("Last updated: February 28, 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    Group {
                        section(title: "1. Acceptance of Terms", content: """
By accessing or using OpenIntelligence ("the App"), you agree to be bound by these Terms of Service. If you do not agree, do not use the App.
""")

                        section(title: "2. Service Description", content: """
OpenIntelligence provides privacy-first document retrieval and AI-powered question answering. The App processes your documents locally whenever possible, with any Apple-managed platform processing or other provider processing controlled by platform availability, user settings, and provider authorization where applicable.
""")

                        section(title: "3. Subscriptions & Billing", content: """
    • **Free Tier**: 5 documents, 1 library, Standard and Deep Think access, Maximum mode limited to \(QuotaPolicy.freeMaximumModeDailyLimit) uses per day
    • **Pro**: Monthly or annual subscription — up to 1,000 documents, 10 libraries, unlimited Maximum mode
    • **Lifetime Cohort**: One-time purchase — unlimited documents, 20 libraries, unlimited Maximum mode
    • **Grandfathered Paid Access**: Prior paid purchases, including legacy document packs, may be treated as Lifetime access in-app
    • **Legacy Document Packs**: Document packs are no longer sold in-app

    Pricing is determined by your App Store region. All subscriptions auto-renew unless cancelled 24 hours before renewal. Manage subscriptions in App Store settings. Cancellation stops future billing but maintains access through the current period.
    """)

                        section(title: "4. Privacy & Data Processing", content: """
• Documents are processed on-device by default
• Cloud processing requires explicit consent for each provider
• We do not sell or share your personal data with third parties
• See Privacy Policy for detailed data handling practices
• You retain all rights to your uploaded documents
""")

                        section(title: "5. Refunds", content: """
Refunds are handled by Apple per their standard policies. Request refunds through App Store support within the applicable refund window.
""")

                        section(title: "6. Acceptable Use", content: """
You agree not to:
• Upload illegal or infringing content
• Attempt to reverse engineer the App
• Share account credentials
• Use the App to violate any applicable laws
• Interfere with app functionality or connected provider services
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
• Website: https://gunzino.me/openintelligence
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

#Preview {
    TermsOfServiceView()
}
