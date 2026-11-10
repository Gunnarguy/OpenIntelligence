//
//  MotherboardHUDView.swift
//  OpenIntelligence
//
//  Full-screen X-Ray overlay showing where the chip sits inside the device, under the screen. The CPU, GPU and
//  Neural Engine are all on one die about a centimetre across, so there is one outline for the chip and one for the
//  Taptic Engine.
//
//  Since 5.8 every position comes from Apple's Self Service Repair images (support.apple.com articles named on each
//  layout), fetched 2026-11-10. Where Apple's images show the logic board but not the chip on it, the outline is the
//  board and is labelled so; no chip spot is guessed. Model identifiers from Apple's support pages and the EveryMac
//  identifier list, fetched 2026-11-10.
//

import Combine
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Device Layout Configuration

/// What an X-Ray outline marks: the chip package itself, or the logic board it sits on.
nonisolated enum PlacementSource: Equatable, Sendable {
    /// The outline is the chip package (the A-series or M-series chip).
    case chip
    /// The chip's exact spot on this model is not known, so the outline is the logic board that holds it.
    case board
}

/// How sure a measured position is.
nonisolated enum PlacementConfidence: Equatable, Sendable {
    case high
    case medium
    case low
    /// No image of this model's insides was found; the spot is the generic one the X-Ray used before 5.8.
    case unsourced
}

/// One outline on the X-Ray.
///
/// `rect` is normalized to the DISPLAY in portrait with the device's top up and the origin at the top left, as
/// fractions of the display's width and height. It is converted from measurements taken on the device outline by
/// `DeviceComponentLayout.displayRect(x:y:)`.
nonisolated struct ComponentPlacement: Equatable, Sendable {
    let rect: CGRect
    let source: PlacementSource
    let confidence: PlacementConfidence
    /// Where the position was measured: Apple support article ids (support.apple.com/<id>) or a teardown.
    let reference: String
}

/// The X-Ray layout for each device the app can run on.
nonisolated enum DeviceComponentLayout: Equatable, Sendable {

    case iPhone15Pro
    case iPhone15ProMax
    case iPhone16
    case iPhone16Plus
    case iPhone16Pro
    case iPhone16ProMax
    case iPhone16e
    case iPhone17
    case iPhoneAir
    case iPhone17e
    case iPhone17Pro
    case iPhone17ProMax
    case iPhone18Pro
    case iPhone18ProMax
    /// iPad mini with A17 Pro or A20 Pro.
    case iPadMini
    /// iPad Air with M2 or later.
    case iPadAir
    /// iPad Pro with M4 or M5.
    case iPadPro
    /// iPad Pro with M1 or M2: no source for its insides.
    case iPadProM1M2
    /// iPad Air with M1: no source for its insides.
    case iPadAirM1
    /// Anything else, including iPhone Duo (iPhone19,4), whose insides are not mapped yet. Shows no outline.
    case unknown

    /// Detect the current device via utsname(). In the Simulator, the simulated model's identifier.
    @MainActor
    static var current: DeviceComponentLayout {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        let layout = Self.layout(forIdentifier: identifier)
        if layout != .unknown { return layout }

        #if targetEnvironment(simulator)
            // The Simulator reports the Mac's architecture from utsname; the simulated model's own identifier is in
            // the environment, so a simulated iPhone 17 Pro gets the iPhone 17 Pro layout.
            let simModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
            let simulated = Self.layout(forIdentifier: simModel)
            if simulated != .unknown { return simulated }
            // An identifier the table has not heard of: the closest layout by screen size, as before 5.8.
            if simModel.hasPrefix("iPhone") {
                let screenHeight = simulatorNativeScreenHeight()
                if screenHeight >= 2796 {
                    return .iPhone16ProMax
                } else if screenHeight >= 2556 {
                    return .iPhone16Pro
                }
            }
        #endif
        return .unknown
    }

    /// The layout for a model identifier such as "iPhone18,3". Unknown identifiers give `.unknown`, which draws no
    /// outline, rather than a guessed spot.
    static func layout(forIdentifier identifier: String) -> DeviceComponentLayout {
        switch identifier {
        case "iPhone16,1": return .iPhone15Pro
        case "iPhone16,2": return .iPhone15ProMax
        case "iPhone17,1": return .iPhone16Pro
        case "iPhone17,2": return .iPhone16ProMax
        case "iPhone17,3": return .iPhone16
        case "iPhone17,4": return .iPhone16Plus
        case "iPhone17,5": return .iPhone16e
        case "iPhone18,1": return .iPhone17Pro
        case "iPhone18,2": return .iPhone17ProMax
        case "iPhone18,3": return .iPhone17
        case "iPhone18,4": return .iPhoneAir
        case "iPhone18,5": return .iPhone17e
        case "iPhone19,2": return .iPhone18Pro
        case "iPhone19,3", "iPhone19,7": return .iPhone18ProMax
        // iPhone19,4 is iPhone Duo, the foldable: no layout yet, so it falls through to `.unknown`.
        default: break
        }

        guard identifier.hasPrefix("iPad") else { return .unknown }
        let numbers = identifier.dropFirst("iPad".count).split(separator: ",").compactMap { Int($0) }
        guard numbers.count == 2 else { return .unknown }
        let (major, minor) = (numbers[0], numbers[1])
        switch (major, minor) {
        case (13, 4...11): return .iPadProM1M2  // iPad Pro M1
        case (13, 16...17): return .iPadAirM1  // iPad Air M1
        case (14, 3...6): return .iPadProM1M2  // iPad Pro M2
        case (14, 8...11): return .iPadAir  // iPad Air M2
        case (15, 3...6): return .iPadAir  // iPad Air M3 (identifiers not verified against a primary source)
        case (16, 1...2): return .iPadMini  // iPad mini A17 Pro
        case (16, 3...6): return .iPadPro  // iPad Pro M4
        case (16, 8...11): return .iPadAir  // iPad Air M4
        case (17, 1...4): return .iPadPro  // iPad Pro M5
        default: return .unknown
        }
    }

    @MainActor
    private static func simulatorNativeScreenHeight() -> CGFloat {
        #if canImport(UIKit)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let screen = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
            return screen?.nativeBounds.height ?? 0
        #else
            return 0
        #endif
    }

    var displayName: String {
        switch self {
        case .iPhone15Pro: return "iPhone 15 Pro"
        case .iPhone15ProMax: return "iPhone 15 Pro Max"
        case .iPhone16: return "iPhone 16"
        case .iPhone16Plus: return "iPhone 16 Plus"
        case .iPhone16Pro: return "iPhone 16 Pro"
        case .iPhone16ProMax: return "iPhone 16 Pro Max"
        case .iPhone16e: return "iPhone 16e"
        case .iPhone17: return "iPhone 17"
        case .iPhoneAir: return "iPhone Air"
        case .iPhone17e: return "iPhone 17e"
        case .iPhone17Pro: return "iPhone 17 Pro"
        case .iPhone17ProMax: return "iPhone 17 Pro Max"
        case .iPhone18Pro: return "iPhone 18 Pro"
        case .iPhone18ProMax: return "iPhone 18 Pro Max"
        case .iPadMini: return "iPad mini"
        case .iPadAir: return "iPad Air"
        case .iPadPro: return "iPad Pro"
        case .iPadProM1M2: return "iPad Pro"
        case .iPadAirM1: return "iPad Air"
        case .unknown: return "Unknown Device"
        }
    }

    /// The chip label shown in the HUD.
    ///
    /// This deliberately does **not** come from the layout table above. That table is an
    /// exact-identifier map and exists to place the outline at the right physical spot
    /// on each board, which genuinely needs per-model data. Using it for the *name* meant
    /// the HUD carried a third, independently-maintained chip table, and it had already
    /// drifted: every `.iPadPro` reported "Apple M4", so an M5 iPad Pro was mislabelled.
    ///
    /// `DeviceCapabilityService` keys iPhones off the major identifier number and Macs off
    /// the CPU brand string, so it resolves hardware this table has never heard of.
    @MainActor
    var chipName: String {
        DeviceCapabilityService.shared.chipName
    }

    // MARK: - Measured positions

    /// How far the display sits inside the device outline on each side, as a fraction of the outline. Apple's locator
    /// images show the whole device, and the display is inset about 1 to 3% from its edge; 2% is assumed on all four
    /// sides to turn an outline measurement into a display one.
    static let displayInset: CGFloat = 0.02

    /// Turns a measurement on the device outline (fractions of the outline, front view, portrait, origin top left)
    /// into the display's normalized space, clamped to the display.
    static func displayRect(x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> CGRect {
        let span = 1 - 2 * displayInset
        func map(_ value: CGFloat) -> CGFloat { min(1, max(0, (value - displayInset) / span)) }
        let x0 = map(x.lowerBound)
        let x1 = map(x.upperBound)
        let y0 = map(y.lowerBound)
        let y1 = map(y.upperBound)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Where the chip is, or the logic board when the chip's spot on that board is not known. Nil draws nothing.
    ///
    /// Measured on Apple's Self Service Repair locator images (the article ids are in each `reference`), fetched
    /// 2026-11-10. The iPad entries are approximate: Apple publishes no logic-board image for them, so they mark the
    /// column the board occupies, never a chip.
    var socPlacement: ComponentPlacement? {
        switch self {
        case .iPhone15Pro:
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.08...0.33, y: 0.30...0.50), source: .chip, confidence: .low,
                reference: "Apple 104882, 104885; board x 0.04-0.36, y 0.17-0.62")
        case .iPhone15ProMax:
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.10...0.33, y: 0.30...0.54), source: .chip, confidence: .low,
                reference: "Apple 104927")
        case .iPhone16:
            // The board is a band across the top (x 0.05-0.65, y 0.03-0.25) and a column down the left; the column
            // is outlined. The chip on it is not located.
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.03...0.22, y: 0.03...0.70), source: .board, confidence: .medium,
                reference: "Apple 120643")
        case .iPhone16Plus:
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.03...0.22, y: 0.03...0.70), source: .board, confidence: .medium,
                reference: "Apple 120672")
        case .iPhone16Pro:
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.05...0.35, y: 0.20...0.66), source: .board, confidence: .medium,
                reference: "Apple 120812")
        case .iPhone16ProMax:
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.05...0.35, y: 0.20...0.66), source: .board, confidence: .medium,
                reference: "Apple 120829; board taken as the 16 Pro's")
        case .iPhone16e:
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.06...0.29, y: 0.20...0.65), source: .board, confidence: .medium,
                reference: "Apple 121696")
        case .iPhone17e:
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.06...0.29, y: 0.20...0.65), source: .board, confidence: .medium,
                reference: "Apple 125950; board taken as the 16e's")
        case .iPhone17:
            // A column down the left plus a band across the top; the column is outlined.
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.02...0.24, y: 0.14...0.64), source: .board, confidence: .medium,
                reference: "Apple 123042, 123045")
        case .iPhoneAir:
            // The whole board sits under the camera area at the top. The chip on it is not located.
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.05...0.96, y: 0.10...0.27), source: .board, confidence: .medium,
                reference: "Apple 123061, 123063")
        case .iPhone17Pro:
            // Confidence low to medium. Board x 0.06-0.95, y 0.20-0.40.
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.30...0.52, y: 0.24...0.36), source: .chip, confidence: .low,
                reference: "Apple 123375, 123372; iFixit CT scan")
        case .iPhone17ProMax:
            // Board x 0.14-0.97, y 0.19-0.36 (Apple 123395, 123392). The chip is assumed to sit where it does on the
            // 17 Pro.
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.30...0.52, y: 0.24...0.36), source: .chip, confidence: .low,
                reference: "Apple 123395, 123392; chip assumed at the 17 Pro's spot")
        case .iPhone18Pro:
            // Confidence medium to high: the chip's cooling mesh shows in Apple's image.
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.27...0.51, y: 0.28...0.40), source: .chip, confidence: .medium,
                reference: "Apple 127411; iFixit teardown")
        case .iPhone18ProMax:
            // Scaled from the 18 Pro. Board main block x 0.15-0.50, y 0.20-0.36.
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.22...0.45, y: 0.22...0.34), source: .chip, confidence: .low,
                reference: "Apple 127646, 127639; chip scaled from the 18 Pro")
        case .iPadPro:
            // APPROXIMATE: no Apple logic-board image exists for iPad. Front view, portrait, USB-C at the bottom.
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.37...0.58, y: 0.16...0.89), source: .board, confidence: .low,
                reference: "approximate, no Apple board image")
        case .iPadAir:
            // APPROXIMATE, as for iPad Pro.
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.74...0.95, y: 0.14...0.87), source: .board, confidence: .low,
                reference: "approximate, no Apple board image")
        case .iPadMini:
            // APPROXIMATE, as for iPad Pro.
            return ComponentPlacement(
                rect: Self.displayRect(x: 0.72...0.96, y: 0.16...0.99), source: .board, confidence: .low,
                reference: "approximate, no Apple board image")
        case .iPadProM1M2:
            // Position not sourced: the generic iPad Pro spot used before 5.8, kept and labelled approximate.
            return ComponentPlacement(
                rect: CGRect(x: 0.42, y: 0.44, width: 0.16, height: 0.12), source: .chip, confidence: .unsourced,
                reference: "position not sourced")
        case .iPadAirM1:
            // Position not sourced: the generic iPad Air spot used before 5.8, kept and labelled approximate.
            return ComponentPlacement(
                rect: CGRect(x: 0.40, y: 0.44, width: 0.20, height: 0.12), source: .chip, confidence: .unsourced,
                reference: "position not sourced")
        case .unknown:
            return nil
        }
    }

    // MARK: - Taptic Engine Position

    /// The Taptic Engine (the haptic motor) near the bottom of the device, in the same display space as
    /// `socPlacement`. Nil on iPad, which has none, and on unknown devices.
    var tapticRect: CGRect? {
        switch self {
        case .iPhone15Pro: return Self.displayRect(x: 0.11...0.39, y: 0.86...0.92)  // Apple 104882
        case .iPhone15ProMax: return Self.displayRect(x: 0.10...0.36, y: 0.87...0.93)  // Apple 104927
        case .iPhone16: return Self.displayRect(x: 0.06...0.26, y: 0.76...0.95)  // Apple 120643
        case .iPhone16Plus: return Self.displayRect(x: 0.06...0.23, y: 0.70...0.88)  // Apple 120672
        case .iPhone16Pro: return Self.displayRect(x: 0.12...0.42, y: 0.87...0.95)  // Apple 120812
        case .iPhone16ProMax: return Self.displayRect(x: 0.18...0.47, y: 0.87...0.98)  // Apple 120829
        case .iPhone16e: return Self.displayRect(x: 0.06...0.29, y: 0.85...0.99)  // Apple 121696
        case .iPhone17e: return Self.displayRect(x: 0.06...0.33, y: 0.80...0.93)  // Apple 125950
        case .iPhone17: return Self.displayRect(x: 0.01...0.24, y: 0.76...0.93)  // Apple 123042
        case .iPhoneAir: return Self.displayRect(x: 0.14...0.41, y: 0.82...0.90)  // Apple 123061
        case .iPhone17Pro: return Self.displayRect(x: 0.53...0.99, y: 0.87...0.96)  // Apple 123375
        case .iPhone17ProMax: return Self.displayRect(x: 0.54...0.92, y: 0.88...0.96)  // Apple 123395
        case .iPhone18Pro: return Self.displayRect(x: 0.58...0.92, y: 0.88...0.94)  // Apple 127411
        case .iPhone18ProMax: return Self.displayRect(x: 0.55...0.91, y: 0.89...0.96)  // Apple 127646
        case .iPadMini, .iPadAir, .iPadPro, .iPadProM1M2, .iPadAirM1, .unknown: return nil
        }
    }
}

// MARK: - Placement math

/// The interface's orientation, in a form the placement math can take on any platform (and in tests).
///
/// The cases mean what `UIInterfaceOrientation`'s do: `landscapeLeft` has the Home button side on the LEFT, so the
/// device's portrait top is on the right of the screen; `landscapeRight` the opposite.
nonisolated enum XRayInterfaceOrientation: Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }

    #if canImport(UIKit)
        init(_ orientation: UIInterfaceOrientation) {
            switch orientation {
            case .portraitUpsideDown: self = .portraitUpsideDown
            case .landscapeLeft: self = .landscapeLeft
            case .landscapeRight: self = .landscapeRight
            default: self = .portrait
            }
        }
    #endif
}

nonisolated enum XRayPlacement {
    /// Maps a rect normalized to the display in portrait (device top up) to points in the interface's coordinates,
    /// for an interface that fills the screen.
    ///
    /// This is the mapping `UIScreen.fixedCoordinateSpace` (always portrait, top up) to the interface does. The app
    /// uses UIKit's own conversion when it has a window (`HardwareXRayOverlay`), which also covers Split View and Stage
    /// Manager windows that do not fill the screen; this is the fallback, and what the tests check.
    ///
    /// Until 5.8 the X-Ray had landscape left and right the wrong way round, so on an iPad turned one way the outline
    /// sat on the far side of the screen from the chip.
    static func interfaceRect(
        forPortraitRect rect: CGRect, orientation: XRayInterfaceOrientation, portraitScreenSize size: CGSize
    ) -> CGRect {
        let w = size.width
        let h = size.height
        // The rect in portrait points.
        let x = rect.minX * w
        let y = rect.minY * h
        let width = rect.width * w
        let height = rect.height * h
        switch orientation {
        case .portrait:
            return CGRect(x: x, y: y, width: width, height: height)
        case .portraitUpsideDown:
            return CGRect(x: w - x - width, y: h - y - height, width: width, height: height)
        case .landscapeLeft:
            // The device's top is on the right: a point's distance from the top becomes its distance from the right
            // edge, and its distance from the left side becomes its distance from the top.
            return CGRect(x: h - y - height, y: x, width: height, height: width)
        case .landscapeRight:
            // The device's top is on the left.
            return CGRect(x: y, y: w - x - width, width: height, height: width)
        }
    }
}

// MARK: - Keyboard Height Observer

/// Tracks keyboard height for floating indicator positioning
#if canImport(UIKit)
    final class KeyboardHeightObserver: ObservableObject {
        @Published var keyboardHeight: CGFloat = 0
        @Published var isKeyboardVisible: Bool = false

        init() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillShow),
                name: UIResponder.keyboardWillShowNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillHide),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )
        }

        @objc private func keyboardWillShow(_ notification: Notification) {
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.keyboardHeight = frame.height
                        self.isKeyboardVisible = true
                    }
                }
            }
        }

        @objc private func keyboardWillHide(_ notification: Notification) {
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.keyboardHeight = 0
                    self.isKeyboardVisible = false
                }
            }
        }
    }
#else
    /// macOS stub — keyboard height is always zero on macOS.
    final class KeyboardHeightObserver: ObservableObject {
        @Published var keyboardHeight: CGFloat = 0
        @Published var isKeyboardVisible: Bool = false
    }
#endif

// MARK: - Full-Screen X-Ray Overlay

/// Transparent overlay with one thin outline where the chip (or its logic board) is, and one for the Taptic Engine.
/// Its colour follows whichever of the CPU, GPU and Neural Engine is busiest.
struct HardwareXRayOverlay: View {
    private var telemetry = HardwareTelemetryState.shared
    @StateObject private var keyboardObserver = KeyboardHeightObserver()
    @EnvironmentObject private var settings: SettingsStore

    private let layout = DeviceComponentLayout.current

    /// Where the outlines are drawn, in this view's own coordinates.
    ///
    /// This has to be `@State`, refreshed from `geometry.size` changes. Reading the scene's orientation straight from
    /// `body` gave SwiftUI no dependency to invalidate on, so nothing re-rendered the overlay when the device turned.
    /// The size change lands after the rotation settles, which is when UIKit's coordinate spaces are correct.
    @State private var frames = XRayFrames()

    var showDeviceInfo: Bool = false
    var showSidebar: Bool = false

    /// Explicit initializer. The synthesized memberwise init inherits `private`
    /// from the private stored properties above, so cross-file callers (e.g.
    /// ChatScreen's `showSidebar:` call) cannot see it under older Swift
    /// compilers; CI failed on exactly that. Keep this internal and defaulted.
    init(showDeviceInfo: Bool = false, showSidebar: Bool = false) {
        self.showDeviceInfo = showDeviceInfo
        self.showSidebar = showSidebar
    }

    /// The outlines' frames in the overlay's coordinates.
    struct XRayFrames: Equatable {
        var soc: CGRect?
        var taptic: CGRect?
    }

    /// Combined intensity from all active components, guaranteed finite.
    ///
    /// The outer `max(0, ...)` is load-bearing rather than cosmetic: a NaN in the FIRST argument
    /// of `max` propagates, so the inner three-way max alone could hand a NaN to every consumer
    /// of this value, including the legend's opacity and several frame dimensions.
    private var totalIntensity: Double {
        max(0.0, min(1.0, max(telemetry.cpuIntensity, telemetry.gpuIntensity, telemetry.aneIntensity)))
    }

    /// Dominant color based on which component is most active. Grey while nothing is.
    private var dominantColor: Color {
        let cpu = telemetry.cpuIntensity
        let gpu = telemetry.gpuIntensity
        let ane = telemetry.aneIntensity

        if totalIntensity <= 0.01 {
            return .gray
        } else if ane >= gpu && ane >= cpu {
            return HardwareComponent.neuralEngine.color  // Purple
        } else if gpu >= cpu {
            return HardwareComponent.gpu.color  // Cyan
        } else {
            return HardwareComponent.cpu.color  // Orange
        }
    }

    /// The label beside the chip outline: the chip's name when the outline is the chip, the board otherwise.
    private var socLabel: String {
        guard let placement = layout.socPlacement else { return "" }
        // "approximate" wherever the place is an estimate (low confidence or no source), so the label never claims
        // more than the repair images show (refuting review, 2026-11-10).
        let approximate = placement.confidence == .low || placement.confidence == .unsourced
        switch placement.source {
        case .board:
            return approximate ? "Logic board, \(layout.chipName) inside, approximate" : "Logic board, \(layout.chipName) inside"
        case .chip:
            return approximate ? "\(layout.chipName), approximate" : layout.chipName
        }
    }

    #if canImport(UIKit)
        /// Reads the settled interface orientation from the active scene.
        static func resolveInterfaceOrientation() -> UIInterfaceOrientation {
            guard
                let scene = UIApplication.shared.connectedScenes.first(where: {
                    $0.activationState == .foregroundActive
                }) as? UIWindowScene
                    ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
            else {
                return .portrait
            }
            return scene.effectiveGeometry.interfaceOrientation
        }

        /// The app's own window in the active scene: the largest visible one, which passes over the legend's small
        /// floating window.
        static func mainWindow() -> UIWindow? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
                return nil
            }
            return scene.windows.filter { !$0.isHidden }.max { a, b in
                a.bounds.width * a.bounds.height < b.bounds.width * b.bounds.height
            }
        }
    #endif

    /// Places a portrait, display-normalized rect in this overlay's coordinates.
    ///
    /// The rect is built in the screen's fixed coordinate space, which is always portrait with the device's top up
    /// (`UIScreen.fixedCoordinateSpace`), and UIKit converts it into the window, so it lands on the same physical
    /// spot in every orientation and in a Split View or Stage Manager window that does not fill the screen. Then it is
    /// moved from window coordinates into this view's, using the view's frame in the window.
    private func overlayRect(for normalized: CGRect, overlayFrame: CGRect) -> CGRect {
        #if canImport(UIKit)
            if let window = Self.mainWindow(), let screen = window.windowScene?.screen {
                let fixed = screen.fixedCoordinateSpace
                let fixedSize = fixed.bounds.size
                let inFixed = CGRect(
                    x: normalized.minX * fixedSize.width,
                    y: normalized.minY * fixedSize.height,
                    width: normalized.width * fixedSize.width,
                    height: normalized.height * fixedSize.height)
                let inWindow = window.convert(inFixed, from: fixed)
                return inWindow.offsetBy(dx: -overlayFrame.minX, dy: -overlayFrame.minY)
            }
            // No window yet: the same mapping by hand, taking the overlay as filling the screen.
            let orientation = XRayInterfaceOrientation(Self.resolveInterfaceOrientation())
            let size = overlayFrame.size
            let portraitSize = orientation.isLandscape ? CGSize(width: size.height, height: size.width) : size
            return XRayPlacement.interfaceRect(
                forPortraitRect: normalized, orientation: orientation, portraitScreenSize: portraitSize)
        #else
            return XRayPlacement.interfaceRect(
                forPortraitRect: normalized, orientation: .portrait, portraitScreenSize: overlayFrame.size)
        #endif
    }

    private func refreshFrames(overlayFrame: CGRect) {
        let updated = XRayFrames(
            soc: layout.socPlacement.map { overlayRect(for: $0.rect, overlayFrame: overlayFrame) },
            taptic: layout.tapticRect.map { overlayRect(for: $0, overlayFrame: overlayFrame) })
        if updated != frames { frames = updated }
    }

    private var isMac: Bool {
        #if os(macOS)
            return true
        #elseif targetEnvironment(macCatalyst)
            return true
        #else
            return ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    var body: some View {
        if isMac {
            EmptyView()
        } else {
            GeometryReader { geometry in
                let screenWidth = geometry.size.width
                let screenHeight = geometry.size.height

                ZStack {
                    // The chip outline shows whenever the HUD is on: faint while idle, brighter as the chip works.
                    if let socFrame = frames.soc, let placement = layout.socPlacement {
                        GlowingSoCBorder(
                            frame: socFrame,
                            color: dominantColor,
                            intensity: totalIntensity,
                            glowMultiplier: settings.hudGlowIntensity,  // User-controlled
                            source: placement.source,
                            label: socLabel,
                            containerSize: geometry.size
                        )
                        .allowsHitTesting(false)
                    }

                    // Show the Taptic Engine outline when haptics fire (if enabled), at its physical location.
                    if let tapticFrame = frames.taptic, settings.hudShowTaptic, telemetry.hapticIntensity > 0.01 {
                        GlowingTapticBorder(
                            frame: tapticFrame,
                            intensity: telemetry.hapticIntensity,
                            glowMultiplier: settings.hudGlowIntensity
                        )
                        .allowsHitTesting(false)
                    }

                    // The legend lives in its own floating passthrough window
                    // (FloatingLegendWindowManager): UIKit navigation chrome
                    // intercepts touches at the window level, so NO view inside
                    // the main window can be grabbed near the top of the screen.
                    // A higher window is the only fundamental fix.
                    Color.clear
                        .frame(width: 1, height: 1)
                        #if canImport(UIKit)
                            .onAppear { FloatingLegendWindowManager.shared.ensureVisible(settings: settings) }
                        #endif

                    // Device info (for debugging only; fixed size kept on the Silicon HUD overlay)
                    if showDeviceInfo {
                        Text("\(layout.displayName)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .position(x: screenWidth / 2, y: screenHeight * 0.02)
                            .allowsHitTesting(false)
                    }
                }
                .ignoresSafeArea()
                // Re-place the outlines once a rotation or a window resize has landed. On rotation the reader's width
                // and height swap, so this fires when the new geometry is real; the second pass, a turn of the run
                // loop later, catches a window whose coordinate space settles after SwiftUI's layout.
                .onAppear { refreshFrames(overlayFrame: geometry.frame(in: .global)) }
                .onChange(of: geometry.size) { _, _ in
                    let overlayFrame = geometry.frame(in: .global)
                    refreshFrames(overlayFrame: overlayFrame)
                    Task { @MainActor in refreshFrames(overlayFrame: overlayFrame) }
                }
                #if canImport(UIKit)
                    // A turn that keeps the size (landscape left to right, a half turn) changes no geometry, so the
                    // device's own orientation change places the outlines again once the interface has turned.
                    .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                        let overlayFrame = geometry.frame(in: .global)
                        Task { @MainActor in refreshFrames(overlayFrame: overlayFrame) }
                    }
                #endif
            }
            // The GeometryReader itself must ignore ALL safe areas (container AND
            // keyboard), not just its content: its frame feeds the physical-position
            // mapping. A safe-area-shrunken reader (nav bar top, home indicator bottom,
            // keyboard) would draw the outlines above their true hardware locations.
            .ignoresSafeArea()
            // Decorative for accessibility (5.7): live hardware numbers that change many times a second and
            // that no task needs. The legend's own window is hidden in UIKit as well (`FloatingLegendWindowManager`).
            .accessibilityHidden(true)
        }
    }
}

// MARK: - X-Ray outline style

/// How the X-Ray's outlines look (5.8): a hairline, no glow, brighter as the part works.
private enum XRayOutlineStyle {
    static let lineWidth: CGFloat = 1
    static let chipCornerRadius: CGFloat = 4
    static let boardCornerRadius: CGFloat = 10
    static let idleOpacity: Double = 0.25
    static let busyOpacity: Double = 0.9
    static let maximumFill: Double = 0.06
    /// The Glow Intensity slider's default (`SettingsStore.hudGlowIntensity`): at it the outline runs from
    /// `idleOpacity` to `busyOpacity`; the slider scales that up or down.
    static let defaultGlow: Double = 0.6

    /// The outline's opacity for an activity level and the user's Glow Intensity, never NaN.
    static func opacity(intensity: Double, glow: Double) -> Double {
        let activity = min(1.0, max(0.0, intensity))
        let scale = min(2.0, max(0.0, glow)) / defaultGlow
        return min(1.0, max(0.0, (idleOpacity + (busyOpacity - idleOpacity) * activity) * scale))
    }
}

// MARK: - Chip outline

/// A hairline outline where the chip (or its logic board) is, with a small label beside it.
private struct GlowingSoCBorder: View {
    let frame: CGRect
    let color: Color
    let intensity: Double
    var glowMultiplier: Double = 0.6
    let source: PlacementSource
    let label: String
    let containerSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cornerRadius: CGFloat {
        source == .chip ? XRayOutlineStyle.chipCornerRadius : XRayOutlineStyle.boardCornerRadius
    }
    private var outlineOpacity: Double {
        XRayOutlineStyle.opacity(intensity: intensity, glow: glowMultiplier)
    }
    private var fillOpacity: Double {
        min(XRayOutlineStyle.maximumFill, XRayOutlineStyle.maximumFill * min(1.0, max(0.0, intensity)))
    }

    /// The label sits just above the outline, or just below it when the outline starts too near the top.
    private var labelCenterY: CGFloat {
        frame.minY > 40 ? frame.minY - 12 : min(containerSize.height - 12, frame.maxY + 12)
    }

    /// The label's leading edge: the outline's, held far enough from the right edge that the label stays on screen.
    private var labelMinX: CGFloat {
        max(8, min(frame.minX, containerSize.width - 200))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color.opacity(fillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(color.opacity(outlineOpacity), lineWidth: XRayOutlineStyle.lineWidth)
                )
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            if !label.isEmpty {
                // A point at the label's leading edge, with the label hung off it: an overlay takes its own size and
                // does not change the layout, so the label needs no measuring to start where the outline starts.
                Color.clear
                    .frame(width: 1, height: 1)
                    .overlay(alignment: .leading) {
                        XRayOutlineLabel(text: label, color: color, opacity: max(0.6 * min(1, glowMultiplier / 0.6), outlineOpacity))
                            .fixedSize()
                    }
                    .position(x: labelMinX, y: labelCenterY)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: intensity)
    }
}

/// The small capsule beside an outline: its name, on the legend's dark blur.
private struct XRayOutlineLabel: View {
    let text: String
    let color: Color
    let opacity: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.black.opacity(SiliconLegend.backingOpacity))
                .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        )
        .opacity(opacity)
    }
}

// MARK: - Taptic Engine outline

/// A hairline outline at the Taptic Engine, shown briefly when haptics fire and faded out after.
private struct GlowingTapticBorder: View {
    let frame: CGRect
    let intensity: Double
    var glowMultiplier: Double = 0.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let hapticColor = HardwareComponent.haptic.color

    private var outlineOpacity: Double {
        XRayOutlineStyle.opacity(intensity: intensity, glow: glowMultiplier)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: XRayOutlineStyle.chipCornerRadius, style: .continuous)
            .fill(hapticColor.opacity(XRayOutlineStyle.maximumFill * min(1.0, max(0.0, intensity))))
            .overlay(
                RoundedRectangle(cornerRadius: XRayOutlineStyle.chipCornerRadius, style: .continuous)
                    .strokeBorder(hapticColor.opacity(outlineOpacity), lineWidth: XRayOutlineStyle.lineWidth)
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: intensity)
    }
}

// MARK: - Floating Taptic Indicator (Above Keyboard)

/// Compact floating indicator that appears above the keyboard when typing.
/// Shows Taptic Engine activity without being blocked by keyboard.
private struct FloatingTapticIndicator: View {
    let intensity: Double
    var glowMultiplier: Double = 0.6

    private let hapticColor = HardwareComponent.haptic.color
    /// Grows with Dynamic Type, capped like the legend's (`SiliconLegend.scale`).
    @ScaledMetric(relativeTo: .caption2) private var dynamicScale: CGFloat = 1
    private var scale: CGFloat { min(dynamicScale, SiliconLegend.maximumScale) }

    var body: some View {
        HStack(spacing: 6 * scale) {
            // Pulsing dot
            Circle()
                .fill(hapticColor.opacity(0.6 + 0.4 * intensity))
                .frame(width: 6 * scale, height: 6 * scale)
                .scaleEffect(0.8 + 0.4 * intensity)

            // Label (Silicon HUD keeps capped @ScaledMetric fixed sizes so the overlay stays compact)
            Text("Taptic")
                .font(.system(size: 10 * scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(hapticColor)
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 5 * scale)
        .background(
            Capsule()
                .fill(Color.black.opacity(SiliconLegend.backingOpacity))
                .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                .overlay(
                    Capsule()
                        .strokeBorder(hapticColor.opacity(0.3 * glowMultiplier), lineWidth: 1)
                )
        )
        .shadow(color: hapticColor.opacity(0.3 * intensity * glowMultiplier), radius: 8)
        // FAST animation for real-time profiler feel
        .animation(.linear(duration: 0.02), value: intensity)
        // Decorative for accessibility (5.7): live hardware numbers that change many times a second and that
        // no task needs. On its own this left the text visible to XCUITest (2026-10-15); the legend's window is
        // hidden in UIKit as well (`FloatingLegendWindowManager`).
        .accessibilityHidden(true)
    }
}

// MARK: - Silicon Legend

/// Tiny, unobtrusive indicator showing users what the HUD represents.
/// Shows each triggered component with % contribution bar.
/// COMPACT: Minimal footprint to avoid interfering with app content.
///
/// Readable since 5.7: its text sat at 35 to 65% white on a 25% black wash, and it failed Apple's contrast
/// audit on every tab (`BenchmarkRuns/2026-10-15-accessibility-audit/`, the only contrast failures there). It
/// now has a solid backing with white text and full-strength component colors, and its sizes follow Dynamic
/// Type up to `maximumScale`, past which an overlay that floats over every screen would cover it.
private struct SiliconLegend: View {
    /// The tint over the blurred backing behind every piece of the X-Ray's text. It was 0.9 black alone, set for the
    /// 2026-10-15 contrast audit; the owner asked for it more see-through (2026-11-10), so the backing is a dark blur
    /// (`backingMaterial`) under 0.65 black: the blur evens out what shows through, so white text and the component
    /// colors keep their contrast.
    static let backingOpacity: Double = 0.65
    /// The most the X-Ray grows with Dynamic Type (about the AX2 size).
    static let maximumScale: CGFloat = 1.8

    @ScaledMetric(relativeTo: .caption2) private var dynamicScale: CGFloat = 1
    private var scale: CGFloat { min(dynamicScale, Self.maximumScale) }
    /// The drag hint's height, which grows when it wraps at large text sizes.
    @State private var hintHeight: CGFloat = 0

    let chipName: String
    let intensity: Double
    let metricsSummary: String
    var activities: [HardwareTelemetryState.ComponentActivity] = []

    /// Set the first time the legend is dragged, so the hint never returns.
    @AppStorage("hudHasBeenDragged") private var hasDraggedLegend: Bool = false

    /// Live available memory. Reads the same `SystemStateMonitor` snapshot the Live
    /// System Monitor card reads, so the HUD and that card cannot disagree.
    @ObservedObject private var systemState = SystemStateMonitor.shared

    private var availableRAMText: String {
        let megabytes = systemState.currentState.availableMemoryMB
        return megabytes >= 1024
            ? String(format: "%.1fG", Double(megabytes) / 1024.0)
            : "\(megabytes)M"
    }

    /// On iPhone the legend is three lines, not six (5.8): the owner found the full one covering the top of
    /// the screen ("I love it ... just smaller", 2026-11-04). iPad and Mac keep the full legend.
    private static var usesCompactLayout: Bool {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
            return UIDevice.current.userInterfaceIdiom == .phone
        #else
            return false
        #endif
    }

    /// One cell of the compact legend: a component's dot, name and reading.
    private struct CompactCell: Identifiable {
        let id: String
        let name: String
        let color: String
        let isActive: Bool
        let reading: String
    }

    private var compactCells: [CompactCell] {
        var cells = activities.filter { $0.percentage >= 0 }.map { activity in
            CompactCell(
                id: activity.name, name: activity.name, color: activity.color, isActive: activity.isActive,
                // Int(Double) traps on a non-finite value; see the full legend's percentage text.
                reading: "\(Int(activity.percentage.isFinite ? activity.percentage : 0))%")
        }
        if let taptic = activities.first(where: { $0.name == "Taptic" }) {
            cells.removeAll { $0.id == taptic.name }
            cells.append(
                CompactCell(
                    id: "Taptic", name: "Tap", color: taptic.color, isActive: taptic.isActive,
                    reading: "\u{00D7}\(taptic.opsCount)"))
        }
        return cells
    }

    @ViewBuilder
    private func compactCell(_ cell: CompactCell) -> some View {
        HStack(spacing: 2 * scale) {
            Circle()
                .fill(componentColor(cell.color).opacity(cell.isActive ? 1 : 0.4))
                .frame(width: 4 * scale, height: 4 * scale)
            Text(cell.name)
                .font(.system(size: 8 * scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(componentColor(cell.color))
            Text(cell.reading)
                .font(.system(size: 8 * scale, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 22 * scale, alignment: .trailing)
        }
    }

    /// The compact legend: the chip with free memory beside it, then the components two to a line.
    @ViewBuilder
    private var compactContent: some View {
        HStack(spacing: 3 * scale) {
            Image(systemName: "cpu")
                .font(.system(size: 9 * scale, weight: .medium))
                .opacity(0.7 + 0.3 * min(1.0, max(0.0, intensity)))
            Text(chipName)
                .font(.system(size: 9 * scale, weight: .semibold, design: .monospaced))
            // A fixed gap, never a Spacer: the legend's floating window takes the legend's size, so a view
            // that grows to the width it is offered grows the window, which offers more, without end. On the
            // owner's iPhone on 2026-11-04 that loop held the main thread until iOS ended the app (0x8BADF00D).
            Color.clear.frame(width: 4 * scale, height: 1)
            Image(systemName: "memorychip")
                .font(.system(size: 6 * scale, weight: .semibold))
                .foregroundStyle(.green)
            Text(availableRAMText)
                .font(.system(size: 8 * scale, weight: .regular, design: .monospaced))
        }
        .foregroundStyle(.white)

        if !activities.isEmpty {
            let cells = compactCells
            Grid(alignment: .leading, horizontalSpacing: 6 * scale, verticalSpacing: 1 * scale) {
                ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { index in
                    GridRow {
                        compactCell(cells[index])
                        if index + 1 < cells.count {
                            compactCell(cells[index + 1])
                        }
                    }
                }
            }
        } else if !metricsSummary.isEmpty {
            Text(metricsSummary)
                .font(.system(size: 8 * scale, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
        } else {
            Text("idle")
                .font(.system(size: 8 * scale, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: (Self.usesCompactLayout ? 1 : 2) * scale) {
            if Self.usesCompactLayout {
                compactContent
            } else {
                // Chip header - compact single line (Silicon HUD keeps capped @ScaledMetric fixed sizes)
                HStack(spacing: 3 * scale) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9 * scale, weight: .medium))
                        // The icon still brightens with activity; the text does not, so it always reads.
                        // `min(1.0, max(0.0, x))` in that order: `min(nan, 1.0)` is nan, `max(0.0, nan)` is 0
                        // (swift probe 2026-09-10), so a NaN intensity cannot reach `.opacity`.
                        .opacity(0.7 + 0.3 * min(1.0, max(0.0, intensity)))
                    Text(chipName)
                        .font(.system(size: 9 * scale, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.white)

                // Per-component breakdown with % contribution bars
                if !activities.isEmpty {
                    // Compute components (ANE/GPU/CPU) — show % contribution
                    ForEach(activities.filter { $0.percentage >= 0 }, id: \.name) { activity in
                        HStack(spacing: 3 * scale) {
                            // Active indicator dot (glows when firing)
                            Circle()
                                .fill(componentColor(activity.color).opacity(activity.isActive ? 1 : 0.4))
                                .frame(width: 4 * scale, height: 4 * scale)

                            // Component name — compact fixed width
                            Text(activity.name)
                                .font(.system(size: 8 * scale, weight: .semibold, design: .monospaced))
                                .foregroundStyle(componentColor(activity.color))
                                .frame(width: 28 * scale, alignment: .leading)

                            // Mini percentage bar - narrower
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    // Track
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(height: 2 * scale)

                                    // Fill
                                    Capsule()
                                        .fill(componentColor(activity.color).opacity(activity.isActive ? 1 : 0.5))
                                        .frame(
                                            // `ComponentActivity` guarantees a finite percentage, and
                                            // geo.size.width is finite by construction. The clamp is
                                            // here anyway because a non-finite frame dimension makes
                                            // SwiftUI assert from inside the body getter, where the
                                            // reported line is the enclosing view rather than this one.
                                            width: max(
                                                1,
                                                min(
                                                    geo.size.width,
                                                    geo.size.width * CGFloat(activity.percentage / 100.0))),
                                            height: 2 * scale)
                                }
                                .frame(height: geo.size.height)
                            }
                            .frame(width: 24 * scale, height: 4 * scale)

                            // Percentage text
                            // Int(Double) TRAPS on a non-finite value, and the `>= 0` filter above does
                            // not screen +infinity. ComponentActivity now guarantees finite,
                            // so this is the second line of defence rather than the first.
                            Text("\(Int(activity.percentage.isFinite ? activity.percentage : 0))%")
                                .font(.system(size: 8 * scale, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(width: 26 * scale, alignment: .trailing)
                        }
                    }

                    // Taptic Engine — separate indicator, not competing with compute %
                    if let taptic = activities.first(where: { $0.name == "Taptic" }) {
                        HStack(spacing: 3 * scale) {
                            Circle()
                                .fill(componentColor(taptic.color).opacity(taptic.isActive ? 1 : 0.4))
                                .frame(width: 4 * scale, height: 4 * scale)

                            Text("Tap")
                                .font(.system(size: 8 * scale, weight: .semibold, design: .monospaced))
                                .foregroundStyle(componentColor(taptic.color))
                                .frame(width: 28 * scale, alignment: .leading)

                            // Show fire count instead of % — it's an output device
                            Text("×\(taptic.opsCount)")
                                .font(.system(size: 8 * scale, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(width: 50 * scale, alignment: .trailing)
                        }
                    }

                    // Available RAM. Not a compute percentage, so it follows Taptic in
                    // the read-only group rather than the bar rows above.
                    HStack(spacing: 3 * scale) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 6 * scale, weight: .semibold))
                            .foregroundStyle(.green)
                            .frame(width: 4 * scale, alignment: .center)

                        Text("RAM")
                            .font(.system(size: 8 * scale, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green)
                            .frame(width: 28 * scale, alignment: .leading)

                        Text(availableRAMText)
                            .font(.system(size: 8 * scale, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 50 * scale, alignment: .trailing)
                    }
                } else if !metricsSummary.isEmpty {
                    // Fallback to compact summary
                    Text(metricsSummary)
                        .font(.system(size: 8 * scale, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                } else {
                    Text("idle")
                        .font(.system(size: 8 * scale, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 4 * scale)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .fill(Color.black.opacity(Self.backingOpacity))
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        // Only animate structural changes (new rows appearing), not every tick
        .animation(.easeOut(duration: 0.4), value: activities.count)
        // Attached to the legend rather than placed on the screen, so it travels with it
        // when dragged and cannot end up pointing at empty space. Retires permanently on
        // the first drag, which is the action it is asking for.
        .overlay(alignment: .topLeading) {
            if !hasDraggedLegend {
                dragHint
                    // Its own width, not the legend's: the hint is one line at the usual text sizes
                    // and wraps inside this at large ones instead of running off the screen.
                    .frame(width: 300, alignment: .leading)
                    // Lifted by its own measured height, so it sits just above the legend however
                    // many lines it takes.
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { hintHeight = $0 }
                    .offset(y: -(hintHeight + 4))
                    .transition(.opacity)
            }
        }
        // Decorative for accessibility (5.7): live hardware numbers that change many times a second and that
        // no task needs. On its own this left the text visible to XCUITest (2026-10-15); the legend's window is
        // hidden in UIKit as well (`FloatingLegendWindowManager`).
        .accessibilityHidden(true)
    }

    /// One-time nudge explaining what the floating readout is and that it can be moved.
    ///
    /// The HUD reads as decoration until someone tells you it is live silicon telemetry,
    /// and it starts life over the navigation bar, so "it can be moved" is the first
    /// useful thing to know about it.
    @ViewBuilder
    private var dragHint: some View {
        // Silicon HUD keeps capped @ScaledMetric fixed sizes so the hint stays compact above the legend
        HStack(spacing: 4 * scale) {
            Image(systemName: "hand.draw")
                .font(.system(size: 9 * scale, weight: .semibold))
            Text("Drag me - This is your Device's hardware X-Ray.")
                .font(.system(size: 9 * scale, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 4 * scale)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .fill(Color.black.opacity(Self.backingOpacity))
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    /// The component colors as the legend's text shows them: lighter than the outlines' (5.8). Measured on iOS 27
    /// Simulator screenshots on 2026-11-10 over a white screen, against the see-through backing, the full-strength
    /// colors read ANE purple 2.3:1, GPU cyan 3.8:1 and CPU orange 4.3:1, under the 4.5:1 small text needs; white read
    /// 9.5:1. These lighter forms, over the 0.65 tint, are meant to clear 4.5:1 and are measured again the same way.
    private func componentColor(_ name: String) -> Color {
        switch name {
        case "purple": return Color(red: 205 / 255, green: 165 / 255, blue: 255 / 255)
        case "cyan": return Color(red: 125 / 255, green: 212 / 255, blue: 247 / 255)
        case "orange": return Color(red: 255 / 255, green: 186 / 255, blue: 92 / 255)
        case "pink": return Color(red: 255 / 255, green: 192 / 255, blue: 216 / 255)
        default: return .white
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("SoC Hardware X-Ray") {
        ZStack {
            Color.black.opacity(0.95)
            HardwareXRayOverlay()
        }
        .ignoresSafeArea()
        .onAppear {
            // Simulate activity for preview using public API
            HardwareTelemetryState.shared.sustain(.embeddingGeneration, active: true, intensity: 0.8)
            HardwareTelemetryState.shared.sustain(.vectorSimilarity, active: true, intensity: 0.4)
            HardwareTelemetryState.shared.sustain(.ragOrchestration, active: true, intensity: 0.3)
            HardwareTelemetryState.shared.reportHaptic(style: "preview")
        }
    }
#endif

#if canImport(UIKit)
    // MARK: - Floating Legend Window (mini-window architecture)

    /// The legend lives in a SMALL floating window sized to the legend itself —
    /// the AssistiveTouch pattern. A window that only covers the legend cannot
    /// block or intercept anything else on screen BY CONSTRUCTION: there is no
    /// hit-test override, no passthrough logic, and no claimed-frame bookkeeping
    /// to go stale. Dragging moves the window via a plain UIKit pan recognizer
    /// (incremental translation, immune to the window moving under the finger).
    @MainActor
    final class FloatingLegendWindowManager: NSObject {
        static let shared = FloatingLegendWindowManager()
        private var window: UIWindow?
        private var cancellables = Set<AnyCancellable>()
        private var isDragging = false
        private var lastContentSize = CGSize(width: 220, height: 140)
        private let margin: CGFloat = 16
        /// True while the welcome screen is up. The legend and its "Drag me" hint wait for it to
        /// close, so the first place they show up is the app itself. Until 5.6 a first launch drew
        /// them on top of the welcome screen, where they read as a debug overlay.
        private var isWelcomeScreenVisible = false
        private var hudEnabled = true
        /// True while the app shows a sheet, a cover or an alert (5.7). The legend floats in a window
        /// above the app's, so over a sheet it covered the sheet's buttons and took their taps: on
        /// 2026-10-15 it sat on the Opened File sheet's Don't Add. UIKit announces no presentation, so
        /// the app's windows are looked at twice a second.
        private var isSomethingPresented = false
        private var presentationTimer: Timer?

        /// Called by the root view whenever the welcome screen appears or closes.
        func setWelcomeScreenVisible(_ visible: Bool) {
            isWelcomeScreenVisible = visible
            applyVisibility()
        }

        private func applyVisibility() {
            window?.isHidden = !hudEnabled || isWelcomeScreenVisible || isSomethingPresented
            publishPlacement()
        }

        /// Tells `HUDLegendPlacement` where the visible box is, so a card at the top of the screen can sit under it.
        private func publishPlacement() {
            guard let w = window, !w.isHidden else {
                HUDLegendPlacement.shared.visibleBox = nil
                return
            }
            HUDLegendPlacement.shared.visibleBox = w.frame.insetBy(dx: margin, dy: margin)
        }

        private func watchPresentations() {
            presentationTimer?.invalidate()
            presentationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkPresentations() }
            }
        }

        private func checkPresentations() {
            guard let legend = window, let scene = legend.windowScene else { return }
            let presented = scene.windows.contains { candidate in
                candidate !== legend && candidate.rootViewController?.presentedViewController != nil
            }
            guard presented != isSomethingPresented else { return }
            isSomethingPresented = presented
            applyVisibility()
        }

        func ensureVisible(settings: SettingsStore) {
            guard window == nil else { return }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
                return
            }

            let host = UIHostingController(rootView: FloatingLegendRoot().environmentObject(settings))
            host.view.backgroundColor = .clear
            // Decorative for accessibility (5.7), set on the window's content in UIKit. The legend's own
            // `accessibilityHidden(true)` did not keep its text out of XCUITest's accessibility audit; with this,
            // no audit issue resolves to an X-Ray element (2026-10-15, iOS 27 Simulator). The audit still reports
            // the drawn text, and while this window is on screen it reports little of the screens behind it
            // (`BenchmarkRuns/2026-10-15-accessibility-audit-xray-off/`). Whether VoiceOver passes over it is not
            // yet checked on a device.
            host.view.accessibilityElementsHidden = true

            let w = UIWindow(windowScene: scene)
            w.rootViewController = host
            w.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
            w.backgroundColor = .clear
            w.frame = initialFrame(in: scene)
            hudEnabled = settings.showSiliconHUD
            window = w
            applyVisibility()
            watchPresentations()

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            host.view.addGestureRecognizer(pan)

            // Window visibility follows the HUD toggle directly — observed here
            // (not from inside the window) so it works even while hidden.
            settings.$showSiliconHUD
                .receive(on: RunLoop.main)
                .sink { [weak self] on in
                    self?.hudEnabled = on
                    self?.applyVisibility()
                }
                .store(in: &cancellables)

            // UIKit can stomp custom window frames to full-screen bounds during
            // scene activation (the relaunch-reset bug): re-assert the saved
            // position whenever the scene activates.
            NotificationCenter.default.publisher(for: UIScene.didActivateNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.reassertFrame() }
                .store(in: &cancellables)

            // Rotation was not handled at all. The window manages its own frame in screen
            // coordinates, so after a rotation it kept a frame computed for the previous
            // orientation until something else happened to reassert it. Reported as black
            // rectangles appearing around the HUD after rotating.
            //
            // Deliberately reuses `reassertFrame`, which is already guarded by `!isDragging`
            // and rebuilds from the persisted centre, so dragging behaviour is untouched.
            // The `.main` hop lets the rotation settle before the frame is recomputed; the
            // overlay above reads its orientation the same way, from geometry after the
            // change rather than from the notification itself.
            NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    DispatchQueue.main.async { self?.reassertFrame() }
                }
                .store(in: &cancellables)
        }

        /// Screen bounds oriented the way the interface currently is.
        ///
        /// `UIScreen.bounds` does not rotate: it reports the native portrait size in every
        /// orientation. Clamping against it meant that in landscape the legend was held
        /// inside a portrait-width region, and a centre persisted there could be out of
        /// range on the way back. Both call sites below used it.
        private func orientedBounds(in scene: UIWindowScene) -> CGRect {
            let b = scene.screen.bounds
            let long = max(b.width, b.height)
            let short = min(b.width, b.height)
            return scene.effectiveGeometry.interfaceOrientation.isLandscape
                ? CGRect(x: 0, y: 0, width: long, height: short)
                : CGRect(x: 0, y: 0, width: short, height: long)
        }

        private func reassertFrame() {
            guard !isDragging, let w = window, let scene = w.windowScene else { return }
            w.frame = targetFrame(contentSize: lastContentSize, in: scene)
            publishPlacement()
        }

        /// Frame derived from the PERSISTED center (never from the window's
        /// current origin, which UIKit may have stomped to zero).
        private func targetFrame(contentSize: CGSize, in scene: UIWindowScene) -> CGRect {
            let d = UserDefaults.standard
            let cx = d.object(forKey: "hudLegendPosX") as? Double ?? -1
            let cy = d.object(forKey: "hudLegendPosY") as? Double ?? -1
            let center = CGPoint(x: cx >= 0 ? cx : 110, y: cy >= 0 ? cy : 145)
            let size = CGSize(width: contentSize.width + margin * 2, height: contentSize.height + margin * 2)
            let b = orientedBounds(in: scene)
            var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
            origin.x = min(max(origin.x, -size.width + 60), b.width - 60)
            origin.y = min(max(origin.y, 0), b.height - 60)
            return CGRect(origin: origin, size: size)
        }

        private func initialFrame(in scene: UIWindowScene) -> CGRect {
            targetFrame(contentSize: lastContentSize, in: scene)
        }

        /// The SwiftUI side reports the legend's rendered size; the window snugs
        /// itself around it (+ grab margin) so it never covers more than the box.
        func legendSizeChanged(_ size: CGSize) {
            guard let w = window, size.width > 1, size.height > 1 else { return }
            lastContentSize = size
            if isDragging {
                // Mid-drag: resize in place; never yank the box out from under
                // the finger.
                var f = w.frame
                f.size = CGSize(width: size.width + margin * 2, height: size.height + margin * 2)
                w.frame = f
            } else {
                // Recompute from the persisted center — self-heals any frame
                // stomp instead of freezing it in (the relaunch-reset bug).
                guard let scene = w.windowScene else { return }
                w.frame = targetFrame(contentSize: size, in: scene)
            }
            publishPlacement()
        }

        @objc private func handlePan(_ g: UIPanGestureRecognizer) {
            guard let w = window else { return }
            if g.state == .began { isDragging = true }
            let t = g.translation(in: w)
            var f = w.frame
            f.origin.x += t.x
            f.origin.y += t.y
            w.frame = f
            g.setTranslation(.zero, in: w)
            if g.state == .ended || g.state == .cancelled {
                isDragging = false
                clampAndPersist()
            }
        }

        private func clampAndPersist() {
            guard let w = window, let scene = w.windowScene else { return }
            let b = orientedBounds(in: scene)
            var f = w.frame
            f.origin.x = min(max(f.origin.x, -f.width + 60), b.width - 60)
            f.origin.y = min(max(f.origin.y, 0), b.height - 60)
            w.frame = f
            UserDefaults.standard.set(Double(f.midX), forKey: "hudLegendPosX")
            UserDefaults.standard.set(Double(f.midY), forKey: "hudLegendPosY")
            // Retires the one-time "Drag me" hint. Set here rather than on gesture start so
            // it only counts once the legend has actually moved and been placed.
            UserDefaults.standard.set(true, forKey: "hudHasBeenDragged")
            publishPlacement()
        }
    }

    /// Where the floating X-Ray legend's box is on screen, in window coordinates, or nil while it is hidden (5.8). The
    /// "Setting up search" card reads it and moves below a legend parked at the top, which covered the card on the
    /// owner's iPhone on 2026-11-10.
    @Observable final class HUDLegendPlacement {
        static let shared = HUDLegendPlacement()
        var visibleBox: CGRect?
    }

    /// Root of the mini floating window: display-only; dragging is handled by the
    /// window-level UIPanGestureRecognizer.
    struct FloatingLegendRoot: View {
        @EnvironmentObject private var settings: SettingsStore
        private var telemetry = HardwareTelemetryState.shared
        private let layout = DeviceComponentLayout.current

        var body: some View {
            ZStack {
                if settings.showSiliconHUD {
                    SiliconLegend(
                        chipName: layout.chipName,
                        intensity: max(
                            max(telemetry.cpuIntensity, telemetry.gpuIntensity),
                            max(telemetry.aneIntensity, telemetry.hapticIntensity)),
                        metricsSummary: settings.hudShowMetrics ? telemetry.compactMetricsSummary : "",
                        activities: settings.hudShowMetrics ? telemetry.componentActivities : []
                    )
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { size in
                        FloatingLegendWindowManager.shared.legendSizeChanged(size)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
#endif
