#!/usr/bin/env swift

import Foundation

/// Utility script that keeps BillingProduct.swift and StoreKitConfiguration.storekit in sync.
/// Run from the repo root: `swift scripts/verify_storekit_products.swift`

enum ScriptError: Error, CustomStringConvertible {
    case fileMissing(String)
    case parsingFailure(String)
    case emptyBillingSet

    var description: String {
        switch self {
        case .fileMissing(let path):
            return "Required file missing: \(path)"
        case .parsingFailure(let context):
            return "Unable to parse \(context)."
        case .emptyBillingSet:
            return "No BillingProduct identifiers were found."
        }
    }
}

let fileManager = FileManager.default
let repoRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let billingPath = "OpenIntelligence/Services/Billing/BillingProduct.swift"
let storeKitPath = "OpenIntelligence/StoreKit/StoreKitConfiguration.storekit"

let billingURL = URL(fileURLWithPath: billingPath, relativeTo: repoRoot)
let storeKitURL = URL(fileURLWithPath: storeKitPath, relativeTo: repoRoot)

guard fileManager.fileExists(atPath: billingURL.path) else {
    fputs("\(ScriptError.fileMissing(billingPath).description)\n", stderr)
    exit(1)
}

guard fileManager.fileExists(atPath: storeKitURL.path) else {
    fputs("\(ScriptError.fileMissing(storeKitPath).description)\n", stderr)
    exit(1)
}

let billingSource = try String(contentsOf: billingURL)
let pattern = #"case\s+\w+\s*=\s*\"([A-Za-z0-9_\.]+)\""#
let regex = try NSRegularExpression(pattern: pattern, options: [])
var billingIdentifiers = Set<String>()

let fullRange = NSRange(billingSource.startIndex..<billingSource.endIndex, in: billingSource)
regex.enumerateMatches(in: billingSource, options: [], range: fullRange) { match, _, _ in
    guard
        let match = match,
        match.numberOfRanges >= 2,
        let range = Range(match.range(at: 1), in: billingSource)
    else { return }
    billingIdentifiers.insert(String(billingSource[range]))
}

guard !billingIdentifiers.isEmpty else {
    fputs("\(ScriptError.emptyBillingSet.description)\n", stderr)
    exit(1)
}

let storeKitData = try Data(contentsOf: storeKitURL)
let rawObject = try JSONSerialization.jsonObject(with: storeKitData, options: [])

guard
    let topLevel = rawObject as? [String: Any],
    let products = topLevel["products"] as? [[String: Any]]
else {
    fputs("\(ScriptError.parsingFailure(storeKitPath).description)\n", stderr)
    exit(1)
}

let storeKitIdentifiers = Set(products.compactMap { $0["id"] as? String })

let missingFromStoreKit = billingIdentifiers.subtracting(storeKitIdentifiers)
let orphanedInStoreKit = storeKitIdentifiers.subtracting(billingIdentifiers)

if missingFromStoreKit.isEmpty && orphanedInStoreKit.isEmpty {
    print("✅ StoreKit catalog matches BillingProduct.swift (\(storeKitIdentifiers.count) products)")
    exit(EXIT_SUCCESS)
}

if !missingFromStoreKit.isEmpty {
    print("❌ Missing products in StoreKit config:\n  - " + missingFromStoreKit.sorted().joined(separator: "\n  - "))
}

if !orphanedInStoreKit.isEmpty {
    print("⚠️ Products present in StoreKit but not BillingProduct:\n  - " + orphanedInStoreKit.sorted().joined(separator: "\n  - "))
}

exit(EXIT_FAILURE)
