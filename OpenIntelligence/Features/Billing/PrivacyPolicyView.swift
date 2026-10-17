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

                    Text("Last updated: October 17, 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    // The same text as gunzino.me/openintelligence/privacy, from one source (5.7). Through
                    // 5.6 this view had its own text: dated May 2026, naming third-party providers the app
                    // does not have and a Settings → Privacy that does not exist, with one sentence cut off.
                    Group {
                        section(title: "Overview", content: """
OpenIntelligence reads, indexes, searches and answers from your documents on your device. It sends passages from your documents to Apple's Private Cloud Compute only when you allow it, under the setting you chose. Libraries you set to iCloud Sync copy their files, passages, embeddings and conversations to your own iCloud. The app has no server of its own, and no third-party AI service, analytics, advertising or tracking code. This policy describes version 5.7, and says where earlier versions differ.
""")
                        section(title: "What Stays on Your Device", content: """
• Importing a document: reading its text, recognizing text in scans and pictures, transcribing audio, cutting it into passages, and the embeddings used to search it.
• Searching, ranking, checking an answer against your documents, and answers written by Apple's on-device model.
• Dictation in the chat field, from 5.7 (Apple's on-device speech recognition).
• The Spotlight entries the app adds (a document's name and a short preview), notifications, Live Activities and widgets. From 5.7, turning off Spotlight Indexing in Settings removes the entries.
• The app's own diagnostics and timings.
""")
                        section(title: "What Can Leave Your Device, and When", content: """
**Apple Private Cloud Compute (iOS, iPadOS and macOS 27):** your question with recent conversation context, the passages chosen as evidence with their document names and page numbers, and the app's instructions to the model. Only when you allow it, under Settings, Private Cloud Compute, "When to allow it" (Never use, Ask when needed, or Allow without asking, which versions before 5.7 call "Allow for Deep Think and Maximum"). When it asks, Show Details on the prompt says why and how much would be sent. With Private Cloud Compute chosen in the model picker, answers are written there whenever it can be reached, and Deep Think's and Maximum's reasoning steps can go there too, each behind the same permission. With Hybrid (Automatic), an answer goes there when its passages don't fit in the on-device model's window, and a Deep Think or Maximum answer also goes there when it draws on more than one document. With On-Device, nothing goes there. A question asked through Siri or Shortcuts follows the same rule; when it would need your permission first, the app opens to ask (from 5.7; earlier versions write that answer on your device). The answer shows which route it used. On iOS and macOS 26, answers are always written on your device. Apple states that Private Cloud Compute deletes your data once the answer is returned, keeps none of it, and that no one but you can access it, not even Apple.

**iCloud Sync (Pro and Lifetime, per library):** a library's files, passages, embeddings and conversations, copied to your own iCloud so your other devices signed in to the same Apple Account see the same library. Only for libraries you set to iCloud Sync; libraries are Local Only unless you change them.

**A web page you add (from 5.7):** when you give the app a web address (Save a Web Page, the Link field of Add to Library, or a web address pasted on the Documents screen), it downloads that page from its site. The site sees an ordinary request from your device, which carries nothing from your library. No cookies are sent or kept.

**Language data for the Atlas (from 5.7):** when a library is written in French, German, Italian, Portuguese, Spanish, Turkish or Chinese and your device doesn't have that language's word classes yet, the Atlas asks your device's system to load them, which it may download, so its labels leave out words such as "gently". The request carries the language and nothing from your library.

**Handoff:** what you have open in Chat or Documents (which library, which document, and the document's name) can be picked up on your other devices through Apple's Handoff.

**The App Store rating:** about once a day the app asks Apple's public App Store lookup for its own rating. The request names the app and carries nothing about you or your documents.

**Crash reports (from 5.7, on iOS and macOS 27):** when the app closes unexpectedly it keeps a report on your device and can offer to email it to the developer, and Settings, About can share the whole report. The report holds the app and system versions, the device model and the part of the app's code that was running, and none of your documents, questions or answers. It leaves your device only if you send or share it. Apple may also share crash data with developers if you allow that in your device's settings.

**Purchases:** subscriptions and purchases go through Apple's App Store. The app never sees payment details.

Apple's own privacy policy covers Private Cloud Compute, iCloud, Handoff and the App Store.
""")
                        section(title: "Storage and Retention", content: """
• **Documents and their passages:** on your device, and in your iCloud for libraries set to iCloud Sync, until you delete them. Deleting a library removes its embeddings and keyword index.
• **Search cache:** past questions and the passages found for them are kept in the app's database on your device, so a question asked again is answered faster. From version 5.7 they're deleted whenever a document is added or deleted and when the app is updated. In earlier versions they stay until the app is removed.
• **Backups:** your device's iCloud backup may include the app's data if backups are on.
""")
                        section(title: "Your Controls", content: """
• Settings, Private Cloud Compute: Never use, Ask when needed, or Allow without asking.
• Each library: Local Only or iCloud Sync, in the library's settings.
• Settings: Spotlight Indexing on or off.
• Delete documents, libraries and conversations in the app, or remove the app.
""")
                        section(title: "Children", content: """
OpenIntelligence is not directed to children under 13 and does not knowingly collect information from them.
""")
                        section(title: "Contact", content: """
For privacy questions: Gunnarguy@me.com
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
        #if os(macOS)
            // A Mac sheet takes its size from its content, and a ScrollView has almost none of its own
            // (`ContainerSettingsSheet` has the same note). Settings, About opens this as a sheet (5.7).
            .frame(minWidth: 520, idealWidth: 640, maxWidth: 800, minHeight: 560, idealHeight: 720, maxHeight: .infinity)
        #endif
    }

    private func section(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            // `LocalizedStringKey` renders the **bold** labels; `Text(String)` showed the asterisks (5.7).
            Text(LocalizedStringKey(content))
                .font(.body)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
    }
}

#Preview {
    PrivacyPolicyView()
}
