import SwiftUI

private struct DemoFeature: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
}

private struct DemoStep: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

private struct EngineCapability: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
}

private struct DemoMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}

private let demoFeatures: [DemoFeature] = [
    DemoFeature(title: "Private document intelligence", detail: "Explains the Apple-native product category and why the engine is more than a wrapper around chat.", symbol: "folder.badge.questionmark"),
    DemoFeature(title: "Grounded-answer pipeline", detail: "Shows the retrieval, answer, review, and uncertainty loop at a public level without publishing ranking logic.", symbol: "checkmark.seal.text.page"),
    DemoFeature(title: "Buyer-ready first stop", detail: "Gives SideProjectors visitors a concrete product surface before any private diligence process starts.", symbol: "briefcase"),
    DemoFeature(title: "App Store funnel", detail: "Points evaluators to the shipped app while keeping the proprietary engine in the private repo.", symbol: "iphone.gen3")
]

private let workflowSteps: [DemoStep] = [
    DemoStep(title: "1. Import", detail: "Users bring documents, scans, images, or technical material into a private library."),
    DemoStep(title: "2. Understand", detail: "The private engine prepares text, layout, tables, figures, and OCR-derived evidence for retrieval."),
    DemoStep(title: "3. Retrieve", detail: "Questions pull relevant source support before answer generation begins."),
    DemoStep(title: "4. Answer", detail: "The app presents grounded answers with review affordances instead of generic chat output."),
    DemoStep(title: "5. Inspect", detail: "Users can check source context, uncertainty, and cited support when accuracy matters.")
]

private let engineCapabilities: [EngineCapability] = [
    EngineCapability(title: "Ingestion", detail: "Turns user-controlled documents into a searchable private workspace.", symbol: "tray.and.arrow.down"),
    EngineCapability(title: "Evidence preservation", detail: "Keeps useful text, table, layout, figure, and OCR context available for later retrieval.", symbol: "doc.text.magnifyingglass"),
    EngineCapability(title: "Library-scoped indexing", detail: "Organizes evidence around app libraries instead of one undifferentiated global pile.", symbol: "books.vertical"),
    EngineCapability(title: "Retrieval before generation", detail: "Finds support first so answers can stay tied to the user's material.", symbol: "point.3.connected.trianglepath.dotted"),
    EngineCapability(title: "Answer review", detail: "Surfaces source context and uncertainty so users can decide whether to trust an answer.", symbol: "checkmark.shield")
]

private let demoMessages: [DemoMessage] = [
    DemoMessage(role: .user, text: "What is OpenIntelligence?"),
    DemoMessage(role: .assistant, text: "It is a native Apple document intelligence app built around a private engine for grounded Q&A over user-controlled material."),
    DemoMessage(role: .user, text: "What does this public repo prove?"),
    DemoMessage(role: .assistant, text: "It shows the product story, privacy posture, public architecture, shipped release history, and a buildable demo shell without exposing the proprietary engine implementation.")
]

struct DemoOverviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                featureGrid
                linksCard
            }
            .padding(20)
        }
        .background(background)
        .navigationTitle("OpenIntelligence")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Public Demo Snapshot")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("A product-facing repo for understanding the shipped app, the private engine, and the public/private boundary.")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                DemoPill(label: "App Store app")
                DemoPill(label: "Engine overview")
                DemoPill(label: "Private source protected")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.22), Color.cyan.opacity(0.14), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What this repo communicates")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            ForEach(demoFeatures) { feature in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(feature.title)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text(feature.detail)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Public entry points")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            Link("App Store listing", destination: URL(string: "https://apps.apple.com/us/app/openintelligence/id6756559175")!)
            Link("SideProjectors listing", destination: URL(string: "https://www.sideprojectors.com/project/78816/openintelligence")!)
            Link("GitHub repository", destination: URL(string: "https://github.com/Gunnarguy/OpenIntelligence")!)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var background: some View {
        LinearGradient(
            colors: [Color.black, Color(red: 0.04, green: 0.08, blue: 0.13), Color(red: 0.08, green: 0.14, blue: 0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct DemoExperienceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                workflowCard
                conversationCard
                artifactCard
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Experience")
    }

    private var workflowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Product workflow")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            ForEach(workflowSteps) { step in
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(step.detail)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Demo conversation")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            ForEach(demoMessages) { message in
                HStack {
                    if message.role == .assistant {
                        messageBubble(for: message, tint: Color.blue.opacity(0.16), alignment: .leading)
                        Spacer(minLength: 32)
                    } else {
                        Spacer(minLength: 32)
                        messageBubble(for: message, tint: Color.primary.opacity(0.08), alignment: .trailing)
                    }
                }
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func messageBubble(for message: DemoMessage, tint: Color, alignment: Alignment) -> some View {
        Text(message.text)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .padding(14)
            .frame(maxWidth: 420, alignment: alignment)
            .background(tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var artifactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What ships publicly")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            Text("This repo ships public docs, release notes, reference material, and a lightweight product-facing app shell. The App Store app and private engine are maintained outside this public source tree.")
                .foregroundStyle(.secondary)

            Text("Sample docs included in the repo")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            VStack(alignment: .leading, spacing: 6) {
                Text("- Docs/TestDocuments/sample_1page.txt")
                Text("- Docs/TestDocuments/sample_technical.md")
                Text("- Docs/TestDocuments/sample_unicode.txt")
            }
            .font(.system(size: 15, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct DemoBoundaryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                engineSummary
                capabilityList

                section(
                    title: "What this public repo proves",
                    body: "The repo shows product positioning, privacy posture, release history, public architecture, reference docs, and a demo shell that can be built without private source access."
                )

                section(
                    title: "What stays private",
                    body: "Ranking logic, thresholds, verification heuristics, indexing details, private prompts, internal tests, SDK packaging, and diligence materials remain in OpenIntelligence-Engine."
                )

                section(
                    title: "How buyer evaluation should work",
                    body: "Public visitors can install the App Store app and inspect this repo. Serious private engine review should move through SideProjectors or direct diligence terms."
                )

                section(
                    title: "Why this boundary exists",
                    body: "The public repo should create confidence and explain the engine. The private repo preserves the implementation value that matters in a sale."
                )
            }
            .padding(20)
        }
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
        .navigationTitle("Engine")
    }

    private var engineSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What the engine is")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("A private Apple-native document intelligence pipeline for importing user material, preserving evidence, retrieving support, and producing grounded answers with source review.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var capabilityList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engine responsibilities")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            ForEach(engineCapabilities) { capability in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: capability.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(capability.title)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text(capability.detail)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(body)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct DemoPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}

#Preview {
    DemoOverviewView()
}
