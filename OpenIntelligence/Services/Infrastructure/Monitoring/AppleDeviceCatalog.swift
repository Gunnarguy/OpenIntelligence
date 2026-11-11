//
//  AppleDeviceCatalog.swift
//  OpenIntelligence
//
//  What Apple publishes about each device, and nothing else (5.8).
//
//  Until 5.8 the device screens showed a Neural Engine figure on every device, and Apple publishes one for ten chips (first counted as seven; three older A-series figures were found on 2026-11-10):
//  the rest (35 for A17 Pro, 38 for A18 Pro, 45 for A19 Pro, 50 for A20 Pro, 18 for M3, 45 for M5, and a formula for
//  chips not yet made) were typed in as estimates or "projections". The same tables named the iPhone 18 Pro Max and
//  the iPhone Air's chips wrongly, called an iPad (A16) an M3 iPad Air, an iPad (10th generation) an M1 iPad Pro and
//  the iPad mini (A20 Pro) an "M7" iPad Pro. This file holds only what can be pointed at: a model's name as Xcode's own
//  device database spells it, the chip Apple's Tech Specs give it, and a Neural Engine figure where Apple stated one.
//

import Foundation

nonisolated enum AppleDeviceCatalog {
    struct Model: Sendable, Equatable {
        /// The model's name as Xcode 27.0's device database spells it.
        let name: String
        /// The chip Apple's Tech Specs or announcement name for the model.
        let chip: String
    }

    /// The model for an identifier such as "iPhone17,2", or nil for one this build does not know.
    ///
    /// Names: Xcode 27.0's `iPhoneOS.platform/usr/standalone/device_traits.db`, column `ProductDescription`, read
    /// 2026-11-10. Three identifiers have no usable name there and come from AppleDB (the same source the X-Ray uses, 2026-11-10):
    /// iPhone19,4 is the iPhone Duo and iPad19,1 and 19,2 the iPad mini (A20 Pro).
    /// Chips: Apple's Tech Specs (support.apple.com/docs/iphone, /docs/ipad) and its newsroom announcements, read
    /// 2026-11-10; the iPhone 17e's from apple.com/iphone-17e/specs ("A19 chip").
    static func model(forIdentifier identifier: String) -> Model? {
        models[identifier]
    }

    private static let models: [String: Model] = {
        var table: [String: Model] = [:]
        func add(_ identifiers: [String], _ name: String, _ chip: String) {
            for identifier in identifiers { table[identifier] = Model(name: name, chip: chip) }
        }
        // iPhone
        add(["iPhone15,4"], "iPhone 15", "A16 Bionic")
        add(["iPhone15,5"], "iPhone 15 Plus", "A16 Bionic")
        add(["iPhone16,1"], "iPhone 15 Pro", "A17 Pro")
        add(["iPhone16,2"], "iPhone 15 Pro Max", "A17 Pro")
        add(["iPhone17,1"], "iPhone 16 Pro", "A18 Pro")
        add(["iPhone17,2"], "iPhone 16 Pro Max", "A18 Pro")
        add(["iPhone17,3"], "iPhone 16", "A18")
        add(["iPhone17,4"], "iPhone 16 Plus", "A18")
        add(["iPhone17,5"], "iPhone 16e", "A18")
        add(["iPhone18,1"], "iPhone 17 Pro", "A19 Pro")
        add(["iPhone18,2"], "iPhone 17 Pro Max", "A19 Pro")
        add(["iPhone18,3"], "iPhone 17", "A19")
        add(["iPhone18,4"], "iPhone Air", "A19 Pro")
        add(["iPhone18,5"], "iPhone 17e", "A19")
        add(["iPhone19,2"], "iPhone 18 Pro", "A20 Pro")
        add(["iPhone19,3", "iPhone19,7"], "iPhone 18 Pro Max", "A20 Pro")
        add(["iPhone19,4"], "iPhone Duo", "A20 Pro")
        // iPad
        add(["iPad13,1", "iPad13,2"], "iPad Air (4th generation)", "A14 Bionic")
        add(["iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7"], "iPad Pro (11-inch) (3rd generation)", "M1")
        add(["iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11"], "iPad Pro (12.9-inch) (5th generation)", "M1")
        add(["iPad13,16", "iPad13,17"], "iPad Air (5th generation)", "M1")
        add(["iPad13,18", "iPad13,19"], "iPad (10th generation)", "A14 Bionic")
        add(["iPad14,1", "iPad14,2"], "iPad mini (6th generation)", "A15 Bionic")
        add(["iPad14,3", "iPad14,4"], "iPad Pro (11-inch) (4th generation)", "M2")
        add(["iPad14,5", "iPad14,6"], "iPad Pro (12.9-inch) (6th generation)", "M2")
        add(["iPad14,8", "iPad14,9"], "iPad Air 11-inch (M2)", "M2")
        add(["iPad14,10", "iPad14,11"], "iPad Air 13-inch (M2)", "M2")
        add(["iPad15,3", "iPad15,4"], "iPad Air 11-inch (M3)", "M3")
        add(["iPad15,5", "iPad15,6"], "iPad Air 13-inch (M3)", "M3")
        add(["iPad15,7", "iPad15,8"], "iPad (A16)", "A16")
        add(["iPad16,1", "iPad16,2"], "iPad mini (A17 Pro)", "A17 Pro")
        add(["iPad16,3", "iPad16,4"], "iPad Pro 11-inch (M4)", "M4")
        add(["iPad16,5", "iPad16,6"], "iPad Pro 13-inch (M4)", "M4")
        add(["iPad16,8", "iPad16,9"], "iPad Air 11-inch (M4)", "M4")
        add(["iPad16,10", "iPad16,11"], "iPad Air 13-inch (M4)", "M4")
        add(["iPad17,1", "iPad17,2"], "iPad Pro 11-inch (M5)", "M5")
        add(["iPad17,3", "iPad17,4"], "iPad Pro 13-inch (M5)", "M5")
        add(["iPad19,1", "iPad19,2"], "iPad mini (A20 Pro)", "A20 Pro")
        return table
    }()

    /// Apple's own Neural Engine figure for a chip, in trillions of operations per second, and the words Apple used,
    /// or nil where Apple published none. Read on Apple's newsroom pages, 2026-11-10: A14 "up to 11 trillion operations
    /// per second" (iPad Air, 2020/09), A15 "15.8 trillion" (iPhone 13 Pro, 2021/09), A16 "nearly 17 trillion" (iPhone
    /// 14 Pro, 2022/09), M1 "11 trillion" (2020/11), M1 Ultra "22 trillion" (2022/03), M2 "15.8 trillion" (2022/06), M2
    /// Pro and M2 Max "15.8 trillion" (2023/01), M2 Ultra "31.6 trillion" (2023/06), M4 "38 trillion" (2024/05). The A17
    /// Pro, A18 and A18 Pro announcements give none (they say "up to 2x faster" and "faster"), nor does any A19, A20, M3
    /// or M5 page, so those return nil and the screens say Apple publishes none. The Metal name drops "Bionic", so both
    /// spellings are listed.
    static func neuralEngineFigure(forChip chip: String) -> (value: Double, text: String)? {
        switch chip {
        case "A14", "A14 Bionic": return (11, "11")
        case "A15", "A15 Bionic": return (15.8, "15.8")
        case "A16", "A16 Bionic": return (17, "nearly 17")
        case "M1": return (11, "11")
        case "M1 Ultra": return (22, "22")
        case "M2", "M2 Pro", "M2 Max": return (15.8, "15.8")
        case "M2 Ultra": return (31.6, "31.6")
        case "M4": return (38, "38")
        default: return nil
        }
    }

    static func neuralEngineTOPS(forChip chip: String) -> Double? { neuralEngineFigure(forChip: chip)?.value }

    /// "38" or "15.8": the figure as a number.
    static func topsDescription(_ tops: Double) -> String {
        tops == tops.rounded() ? String(Int(tops)) : String(format: "%.1f", tops)
    }

    /// The chip name inside a Metal device name: "Apple A18 Pro GPU" (the owner's iPhone 16 Pro Max, its trace
    /// 2026-11-07) gives "A18 Pro", and "Apple M3 Pro" (an M3 Pro Mac) gives "M3 Pro". Nil for a name that does not
    /// start with "Apple ", so a renamed or virtual device falls back to the table.
    static func chipName(fromMetalDeviceName name: String) -> String? {
        guard name.hasPrefix("Apple ") else { return nil }
        var chip = String(name.dropFirst("Apple ".count))
        if chip.hasSuffix(" GPU") { chip = String(chip.dropLast(" GPU".count)) }
        chip = chip.trimmingCharacters(in: .whitespaces)
        guard let first = chip.first, first == "A" || first == "M", chip.count >= 2 else { return nil }
        return chip
    }

    /// Memory as the system reports it, to a tenth of a gigabyte (a value within 0.05 of a whole number shows as whole):
    /// Apple publishes no RAM for any iPhone, and
    /// `ProcessInfo.physicalMemory` reads about 7.5 GB on the owner's iPhone 16 Pro Max (2026-11-10), so a whole
    /// number would be a figure the device did not report. "18 GB" for 18.0, "7.5 GB" for 7.47.
    static func memoryDescription(gigabytes: Double) -> String {
        let tenths = (gigabytes * 10).rounded() / 10
        return tenths == tenths.rounded() ? "\(Int(tenths)) GB" : String(format: "%.1f GB", tenths)
    }
}
