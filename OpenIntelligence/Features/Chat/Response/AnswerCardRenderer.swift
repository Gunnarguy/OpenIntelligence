//
//  AnswerCardRenderer.swift
//  OpenIntelligence
//

import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// An answer drawn as a picture, with the documents it cites, the app's name and a code that
/// opens the app's App Store page, for posting where plain text would lose its sources (5.7).
///
/// Rendered with `ImageRenderer` and handed to the share sheet as a PNG file, which Messages, Mail,
/// Photos and the social apps take on iPhone, iPad and Mac alike. The colours are fixed rather
/// than following the system's appearance, so the picture reads the same wherever it is posted.
@MainActor
enum AnswerCardRenderer {
    /// Points wide. At `scale` the picture is 1,170 pixels across, a phone screen's width.
    static let width: CGFloat = 390
    static let scale: CGFloat = 3
    /// A longer answer is cut at a sentence or a word and ends with an ellipsis. The card is for
    /// reading at a glance; Share keeps the whole answer as text.
    nonisolated static let maxAnswerCharacters = 900
    nonisolated static let maxSources = 5

    /// The answer as the card shows it.
    nonisolated static func cardText(_ answer: String, limit: Int = maxAnswerCharacters) -> String {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit, limit > 1 else { return trimmed }
        let head = String(trimmed.prefix(limit - 1))
        // The last sentence end in the second half of what fits, else the last space.
        let sentenceEnds = [". ", "! ", "? ", ".\n", "!\n", "?\n"].compactMap { head.range(of: $0, options: .backwards) }
        if let end = sentenceEnds.max(by: { $0.lowerBound < $1.lowerBound }),
            head.distance(from: head.startIndex, to: end.lowerBound) >= limit / 2
        {
            return String(head[...end.lowerBound]) + " …"
        }
        if let space = head.lastIndex(of: " ") {
            return String(head[..<space]) + "…"
        }
        return head + "…"
    }

    /// Writes the card for an answer to a PNG file in the temporary folder and returns its
    /// address, or nil when it could not be drawn.
    static func renderFile(for message: ChatMessage) -> URL? {
        let sources = AnswerShareFormatter.sources(
            answer: message.content,
            evidence: message.structuredAnswer?.evidence ?? [],
            retrievedChunks: message.retrievedChunks ?? []
        )
        let card = AnswerCardView(
            answer: cardText(message.content),
            sources: Array(sources.prefix(maxSources)),
            moreSources: max(0, sources.count - maxSources),
            code: qrCode(for: OpenIntelligenceLinks.sharedAppStoreURL)
        )
        guard let data = pngData(of: card) else { return nil }
        // A folder of its own for each card, so a second share cannot overwrite the first while the
        // share sheet still holds it; the file keeps the name the person sees.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnswerCards", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("OpenIntelligence Answer.png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.warning("[Share] The answer card could not be written: \(error.localizedDescription)", category: .ui)
            return nil
        }
    }

    /// The PNG bytes of a view drawn at the card's width and scale.
    static func pngData(of view: some View) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// A QR code for an address, one module per pixel; the card scales it up without smoothing.
    nonisolated static func qrCode(for url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent)
    }
}

/// What the card shows. Built only by `AnswerCardRenderer`.
struct AnswerCardView: View {
    let answer: String
    let sources: [AnswerShareFormatter.Source]
    let moreSources: Int
    let code: CGImage?

    private let ink = Color(red: 0.09, green: 0.11, blue: 0.15)
    private let muted = Color(red: 0.36, green: 0.40, blue: 0.46)
    private let accent = Color(red: 0.05, green: 0.42, blue: 0.43)

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "sparkles")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(accent)
                Text("OpenIntelligence")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(ink)
            }

            Text(rendered(answer))
                .scaledFont(size: 16)
                .foregroundStyle(ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if !sources.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Sources")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(muted)
                    ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                        Text(AnswerShareFormatter.line(for: source))
                            .scaledFont(size: 12)
                            .foregroundStyle(ink.opacity(0.8))
                            .lineLimit(2)
                    }
                    if moreSources > 0 {
                        Text("and \(moreSources) more")
                            .scaledFont(size: 12)
                            .foregroundStyle(muted)
                    }
                }
                .padding(.top, DSSpacing.xxs)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(AnswerShareFormatter.attribution)
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundStyle(ink)
                    // The App Store subtitle, word for word.
                    Text("Chat With Your Files Offline, on the App Store")
                        .scaledFont(size: 11)
                        .foregroundStyle(muted)
                }
                Spacer(minLength: DSSpacing.md)
                if let code {
                    Image(decorative: code, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 58, height: 58)
                }
            }
        }
        .padding(DSSpacing.xl)
        .background(Color.white)
    }

    private func rendered(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }
}
