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
    DemoFeature(title: "Private document workflows", detail: "Shows the product category, trust posture, and Apple-native UX direction.", symbol: "folder.badge.questionmark"),
    DemoFeature(title: "Grounded-answer experience", detail: "Demonstrates how the product presents evidence-first answers instead of generic chat vibes.", symbol: "checkmark.seal.text.page"),
    DemoFeature(title: "Founder-ready diligence signal", detail: "Keeps public materials, screenshots, docs, and architecture summaries visible without shipping the private moat.", symbol: "briefcase"),
    DemoFeature(title: "Product framing", detail: "Carries public release notes, privacy posture, and the product-facing story for the shipped app.", symbol: "iphone.gen3")
]

private let workflowSteps: [DemoStep] = [
    DemoStep(title: "1. Import", detail: "The shipped product ingests private documents and prepares them locally."),
    DemoStep(title: "2. Retrieve", detail: "The private engine finds supporting evidence before answer generation."),
    DemoStep(title: "3. Answer", detail: "Answers are designed to stay grounded in the provided material."),
    DemoStep(title: "4. Review", detail: "Users inspect support details, citations, and uncertainty in the product UI.")
]

private let demoMessages: [DemoMessage] = [
    DemoMessage(role: .user, text: "What does this public repo actually show?"),
    DemoMessage(role: .assistant, text: "This repo is a curated public demo snapshot. It shows the product surface, docs, trust model, and public-facing app story without exposing the private engine implementation."),
    DemoMessage(role: .user, text: "What stays private?"),
    DemoMessage(role: .assistant, text: "Retrieval logic, verification heuristics, ingestion internals, embedding/vector search, SDK packaging, and commercialization materials stay in the private engine repo.")
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

            Text("A product-facing, SideProjectors-ready repo that explains what OpenIntelligence is, what users see, and what stays private.")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                DemoPill(label: "Public docs")
                DemoPill(label: "Demo app")
                DemoPill(label: "Private engine kept out")
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
            Text("What this repo is for")
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

            Text("This demo repo keeps docs, release notes, and a lightweight product-facing app shell. It does not ship the private engine implementation.")
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
                section(
                    title: "What stays in this repo",
                    body: "A curated demo app shell, public docs, release notes, and product-facing architecture summaries."
                )

                section(
                    title: "What stays private",
                    body: "Document processing internals, chunking, retrieval, verification, embeddings, vector search, SDK packaging, buyer packets, and commercialization materials remain in OpenIntelligence-Engine."
                )

                section(
                    title: "How updates happen",
                    body: "Private development happens in OpenIntelligence-Engine. The public repo is regenerated from that repo using an allowlist export plus a fail-closed boundary audit."
                )

                section(
                    title: "Why this exists",
                    body: "The public repo is for product signal and demo positioning. The private repo is the actual engine, SDK, and sale/evaluation workspace."
                )
            }
            .padding(20)
        }
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
        .navigationTitle("Boundary")
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
