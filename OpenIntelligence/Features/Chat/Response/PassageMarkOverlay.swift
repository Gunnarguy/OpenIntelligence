//
//  PassageMarkOverlay.swift
//  OpenIntelligence
//
//  The box drawn around a cited passage on a PDF page, in the app's accent color, drawn in once when it appears (5.8).
//

import PDFKit
import SwiftUI
import Vision
import ImageIO

#if canImport(UIKit)
    import UIKit
    typealias PassageMarkPlatformView = UIView
    typealias PassageMarkPlatformColor = UIColor
#else
    import AppKit
    typealias PassageMarkPlatformView = NSView
    typealias PassageMarkPlatformColor = NSColor
#endif

/// The look shared by every cited-passage mark: a rounded box in the app's accent color around the passage, with the
/// lines inside tinted, drawn in once (Reduce Motion shows it at once).
enum PassageMarkStyle {
    static let cornerRadius: CGFloat = 6
    static let lineWidth: CGFloat = 2
    /// How far the box stands off the text, in the page's points.
    static let outset: CGFloat = 3
    static let lineTintOpacity: CGFloat = 0.22
    static let drawInSeconds: CFTimeInterval = 0.7

    static var accent: PassageMarkPlatformColor { PassageMarkPlatformColor(DSColors.accent) }

    static var reduceMotion: Bool {
        #if canImport(UIKit)
            UIAccessibility.isReduceMotionEnabled
        #else
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #endif
    }

    /// Each piece's box on each page, in page space: the union of the piece's line bounds on that page, stood off the
    /// text by `outset`. A piece that runs over a page edge gets a box on both pages.
    static func boxes(for selections: [PDFSelection]) -> [PDFPage: [CGRect]] {
        var boxes: [PDFPage: [CGRect]] = [:]
        for selection in selections {
            var perPage: [PDFPage: CGRect] = [:]
            for line in selection.selectionsByLine() {
                for page in line.pages {
                    let bounds = line.bounds(for: page)
                    guard !bounds.isEmpty else { continue }
                    perPage[page] = perPage[page].map { $0.union(bounds) } ?? bounds
                }
            }
            for (page, box) in perPage {
                boxes[page, default: []].append(box.insetBy(dx: -outset, dy: -outset))
            }
        }
        return boxes
    }
}

/// The view laid over one page, holding that page's boxes. It takes no touches, so the page stays selectable.
final class PassageMarkPageView: PassageMarkPlatformView {
    /// The boxes in page space, and the page box they are measured in.
    private let boxes: [CGRect]
    /// Lines to tint, in page space: a scanned page's, which PDFKit has no text to tint.
    private let lines: [CGRect]
    private let pageBox: CGRect
    private var shapes: [CAShapeLayer] = []
    private let lineTint = CAShapeLayer()
    private var drawnIn = false

    init(boxes: [CGRect], lines: [CGRect] = [], pageBox: CGRect) {
        self.boxes = boxes
        self.lines = lines
        self.pageBox = pageBox
        super.init(frame: .zero)
        #if canImport(UIKit)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        #else
            wantsLayer = true
        #endif
        lineTint.fillColor = PassageMarkStyle.accent.withAlphaComponent(PassageMarkStyle.lineTintOpacity).cgColor
        platformLayer.addSublayer(lineTint)
        for _ in boxes {
            let shape = CAShapeLayer()
            shape.fillColor = PassageMarkStyle.accent.withAlphaComponent(0.06).cgColor
            shape.strokeColor = PassageMarkStyle.accent.cgColor
            shape.lineWidth = PassageMarkStyle.lineWidth
            shape.lineJoin = .round
            shape.lineCap = .round
            platformLayer.addSublayer(shape)
            shapes.append(shape)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var platformLayer: CALayer {
        #if canImport(UIKit)
            layer
        #else
            layer!
        #endif
    }

    #if canImport(UIKit)
        override func layoutSubviews() {
            super.layoutSubviews()
            placeShapes()
        }
    #else
        override func layout() {
            super.layout()
            placeShapes()
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #endif

    /// Page space runs up from the bottom; UIKit's view space runs down from the top.
    private func viewRect(for box: CGRect) -> CGRect {
        guard pageBox.width > 0, pageBox.height > 0 else { return .zero }
        let scaleX = bounds.width / pageBox.width
        let scaleY = bounds.height / pageBox.height
        let x = (box.minX - pageBox.minX) * scaleX
        #if canImport(UIKit)
            let y = (pageBox.maxY - box.maxY) * scaleY
        #else
            let y = (box.minY - pageBox.minY) * scaleY
        #endif
        return CGRect(x: x, y: y, width: box.width * scaleX, height: box.height * scaleY)
    }

    private func placeShapes() {
        guard bounds.width > 0 else { return }
        let scale = bounds.width / max(pageBox.width, 1)
        let tints = CGMutablePath()
        for line in lines {
            tints.addRoundedRect(in: viewRect(for: line), cornerWidth: 2 * scale, cornerHeight: 2 * scale)
        }
        lineTint.frame = bounds
        lineTint.path = tints
        for (shape, box) in zip(shapes, boxes) {
            let rect = viewRect(for: box)
            shape.frame = bounds
            shape.path = CGPath(
                roundedRect: rect, cornerWidth: PassageMarkStyle.cornerRadius * scale,
                cornerHeight: PassageMarkStyle.cornerRadius * scale, transform: nil)
            shape.lineWidth = max(1.5, PassageMarkStyle.lineWidth * scale)
        }
        guard !drawnIn else { return }
        drawnIn = true
        guard !PassageMarkStyle.reduceMotion else { return }
        for shape in shapes {
            let drawIn = CABasicAnimation(keyPath: "strokeEnd")
            drawIn.fromValue = 0
            drawIn.toValue = 1
            drawIn.duration = PassageMarkStyle.drawInSeconds
            drawIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shape.add(drawIn, forKey: "drawIn")
        }
    }
}

/// The same mark in SwiftUI, behind a passage shown as text (`SourceTextView`: Word, text, web pages, spreadsheets,
/// recordings, images read by OCR).
struct PassageMarkBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
            .fill(DSColors.accent.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                    .trim(from: 0, to: drawn)
                    .stroke(DSColors.accent, style: StrokeStyle(lineWidth: PassageMarkStyle.lineWidth, lineCap: .round))
            )
            .onAppear {
                if reduceMotion {
                    drawn = 1
                } else {
                    withAnimation(.easeOut(duration: PassageMarkStyle.drawInSeconds)) { drawn = 1 }
                }
            }
    }
}

/// A scanned page's marks: the page has no text layer, so Vision reads its image, the passage is found in what it read
/// (`PassageFinder`), and Vision gives where each of the passage's lines sits (`boundingRegion(for:)`, iOS 26 and
/// macOS 26). Each piece is its lines' tints and one box around them, in page space.
enum ScannedPageMarks {
    struct Marks: Sendable {
        var boxes: [CGRect] = []
        var lines: [CGRect] = []
    }

    /// The page as an image, about 2,000 points on its long side: enough for Vision to read body text.
    @MainActor static func image(of page: PDFPage, box: PDFDisplayBox) -> OCRHandoff<CGImage>? {
        let bounds = page.bounds(for: box)
        let scale = 2_000 / max(bounds.width, bounds.height, 1)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        #if canImport(UIKit)
            guard let image = page.thumbnail(of: size, for: box).cgImage else { return nil }
        #else
            guard let image = page.thumbnail(of: size, for: box).cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return nil }
        #endif
        return OCRHandoff(value: image)
    }

    /// Off the main actor: Vision reads the page, and the passage's lines are placed on it.
    @concurrent static func marks(
        for passage: String, in image: OCRHandoff<CGImage>, pageBox: CGRect, outset: CGFloat = PassageMarkStyle.outset
    ) async -> Marks {
        guard let observation = try? await RecognizeDocumentsRequest().perform(on: image.value).first else {
            return Marks()
        }
        let text = observation.document.text
        let transcript = text.transcript
        let source = transcript as NSString
        var marks = Marks()
        for piece in PassageFinder.places(passage, in: transcript) {
            var pieceLines: [CGRect] = []
            source.enumerateSubstrings(in: piece, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
                guard line.length > 0, let range = Range(line, in: transcript),
                    let region = text.boundingRegion(for: range)
                else { return }
                // Vision's box is a share of the image from its lower left, as page space runs.
                let box = region.normalizedPath.boundingBox
                pieceLines.append(
                    CGRect(
                        x: pageBox.minX + box.minX * pageBox.width, y: pageBox.minY + box.minY * pageBox.height,
                        width: box.width * pageBox.width, height: box.height * pageBox.height))
            }
            guard let first = pieceLines.first else { continue }
            marks.lines += pieceLines
            marks.boxes.append(
                pieceLines.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -outset, dy: -outset))
        }
        return marks
    }
}

/// A cited image (a photo, a screenshot, a scan saved as an image) with the passage boxed where Vision reads it (5.8),
/// shown above the text the app read from it in `SourceTextView`.
struct SourceImageMarkView: View {
    let url: URL
    let passage: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: CGImage?
    @State private var marks = ScannedPageMarks.Marks()
    @State private var drawn: CGFloat = 0

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        GeometryReader { geometry in
                            let size = CGSize(width: image.width, height: image.height)
                            ZStack(alignment: .topLeading) {
                                ForEach(Array(marks.lines.enumerated()), id: \.offset) { _, line in
                                    let rect = Self.viewRect(line, image: size, view: geometry.size)
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(DSColors.accent.opacity(Double(PassageMarkStyle.lineTintOpacity)))
                                        .frame(width: rect.width, height: rect.height)
                                        .offset(x: rect.minX, y: rect.minY)
                                }
                                ForEach(Array(marks.boxes.enumerated()), id: \.offset) { _, box in
                                    let rect = Self.viewRect(box, image: size, view: geometry.size)
                                    RoundedRectangle(cornerRadius: PassageMarkStyle.cornerRadius, style: .continuous)
                                        .trim(from: 0, to: drawn)
                                        .stroke(DSColors.accent, style: StrokeStyle(lineWidth: PassageMarkStyle.lineWidth, lineCap: .round))
                                        .frame(width: rect.width, height: rect.height)
                                        .offset(x: rect.minX, y: rect.minY)
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                    .accessibilityLabel(Text("The image, with the passage marked"))
            }
        }
        .task(id: passage) {
            guard let loaded = Self.load(url) else { return }
            image = loaded.value
            let box = CGRect(x: 0, y: 0, width: loaded.value.width, height: loaded.value.height)
            marks = await ScannedPageMarks.marks(for: passage, in: loaded, pageBox: box, outset: 8)
            VerificationJournal.record("citation.highlight", ["found": "\(!marks.boxes.isEmpty)", "image": "true"])
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(.easeOut(duration: PassageMarkStyle.drawInSeconds)) { drawn = 1 }
            }
        }
    }

    /// An image box (pixels, from the lower left) in the view's points (from the top left).
    static func viewRect(_ box: CGRect, image: CGSize, view: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scaleX = view.width / image.width
        let scaleY = view.height / image.height
        return CGRect(
            x: box.minX * scaleX, y: (image.height - box.maxY) * scaleY, width: box.width * scaleX,
            height: box.height * scaleY)
    }

    /// The image upright, at most 2,400 pixels on its long side.
    static func load(_ url: URL) -> OCRHandoff<CGImage>? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_400,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { OCRHandoff(value: $0) }
    }
}
