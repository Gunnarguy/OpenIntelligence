// Draws the App Store promotional images for the two Pro subscriptions into fastlane/iap_images/.
//
// Apple's rules for these images: 1024 x 1024, JPG or PNG, RGB, flattened, no rounded corners
// (App Store Connect Help, "View and edit In-App Purchase information"); unique to the purchase,
// not a screenshot, not confusable with the app icon, and no text laid over it
// (developer.apple.com/app-store/promoting-in-app-purchases, read 2026-09-23).
//
// The symbol is the flame the app shows for Maximum mode, which is the cap a Pro plan lifts. Monthly
// is the flame on orange to red; Annual adds a ring and runs orange to purple, so the two differ.
// The app icon is a lightbulb on blue.
//
// Usage, from the repository root:
//   xcrun swift scripts/render_iap_images.swift
// scripts/asc_listing_extras.rb uploads the results.

import AppKit
import ImageIO
import UniformTypeIdentifiers

func render(_ path: String, _ top: NSColor, _ bottom: NSColor, ring: Bool) {
    let side = 1024
    // noneSkipLast: an opaque RGB image with no alpha channel, which is what "flattened" requires.
    let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    NSGradient(starting: top, ending: bottom)!.draw(in: NSRect(x: 0, y: 0, width: side, height: side), angle: -60)
    let center = NSPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
    if ring {
        let ringPath = NSBezierPath(ovalIn: NSRect(x: center.x - 392, y: center.y - 392, width: 784, height: 784))
        ringPath.lineWidth = 26
        NSColor.white.withAlphaComponent(0.85).setStroke()
        ringPath.stroke()
    }

    let config = NSImage.SymbolConfiguration(pointSize: ring ? 400 : 470, weight: .semibold)
    let glyph = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let white = NSImage(size: glyph.size, flipped: false) { rect in
        glyph.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 36
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    white.draw(
        at: NSPoint(x: center.x - white.size.width / 2, y: center.y - white.size.height / 2),
        from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    let url = URL(fileURLWithPath: path)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    let properties = [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72] as CFDictionary
    CGImageDestinationAddImage(destination, context.makeImage()!, properties)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(path)") }
    print("wrote \(path)")
}

let orange = NSColor(srgbRed: 1.00, green: 0.62, blue: 0.04, alpha: 1)
let red = NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)
let purple = NSColor(srgbRed: 0.75, green: 0.35, blue: 0.95, alpha: 1)
render("fastlane/iap_images/pro_monthly.png", orange, red, ring: false)
render("fastlane/iap_images/pro_annual.png", orange, purple, ring: true)
