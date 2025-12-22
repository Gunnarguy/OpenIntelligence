#!/usr/bin/env swift

import CryptoKit
import Dispatch
import Foundation

/// CLI script to confirm that App Store Connect knows about our StoreKit product identifiers.
///
/// This does NOT execute a StoreKit purchase flow (that requires device/sandbox context).
/// Instead it queries the App Store Connect API and prints which product IDs are present.
///
/// Usage (from repo root):
///   swift scripts/check_app_store_connect_products.swift
///
/// Required env:
///   APP_STORE_CONNECT_ISSUER
///   APP_STORE_CONNECT_KEY_ID
///   APP_STORE_CONNECT_PRIVATE_KEY_PATH
/// Optional env:
///   APP_STORE_CONNECT_BUNDLE_ID (defaults to Gunndamental.OpenIntelligence)

enum CLIError: Error, CustomStringConvertible {
    case missingEnv(String)
    case fileUnreadable(String)
    case badURL(String)
    case requestFailed(String)
    case decodeFailed(String)
    case appNotFound(String)

    var description: String {
        switch self {
        case let .missingEnv(name):
            return "Missing required env var: \(name)"
        case let .fileUnreadable(path):
            return "Unable to read file: \(path)"
        case let .badURL(raw):
            return "Invalid URL: \(raw)"
        case let .requestFailed(message):
            return message
        case let .decodeFailed(context):
            return "Unable to parse response: \(context)"
        case let .appNotFound(bundleId):
            return "No App found in App Store Connect for bundleId=\(bundleId)."
        }
    }
}

private func loadDotEnvIfPresent(repoRoot: URL) -> [String: String] {
    // Intentionally minimal parser: KEY=VALUE, optional quoting, ignores comments.
    // This is purely for local developer convenience. CI should inject env vars normally.
    let url = URL(fileURLWithPath: ".env", relativeTo: repoRoot)
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

    var out: [String: String] = [:]
    for line in raw.split(whereSeparator: \.isNewline) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        guard !trimmed.hasPrefix("#") else { continue }

        // Allow a common pattern: export KEY=VALUE
        let normalized = trimmed.hasPrefix("export ") ? String(trimmed.dropFirst("export ".count)) : trimmed
        guard let eq = normalized.firstIndex(of: "=") else { continue }

        let key = normalized[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
        var value = String(normalized[normalized.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)

        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        guard !key.isEmpty else { continue }
        out[String(key)] = value
    }
    return out
}

private func configValue(_ name: String, dotenv: [String: String]) -> String {
    // Shell env vars take precedence over .env.
    let fromEnv = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !fromEnv.isEmpty { return fromEnv }
    return (dotenv[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func configRequired(_ name: String, dotenv: [String: String]) throws -> String {
    let value = configValue(name, dotenv: dotenv)
    guard !value.isEmpty else { throw CLIError.missingEnv(name) }
    return value
}

private func configOptional(_ name: String, default defaultValue: String, dotenv: [String: String]) -> String {
    let value = configValue(name, dotenv: dotenv)
    return value.isEmpty ? defaultValue : value
}

private func base64url(_ data: Data) -> String {
    let b64 = data.base64EncodedString()
    return b64
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func makeASCJWT(issuer: String, keyID: String, privateKeyPEM: String) throws -> String {
    // ASC requires: aud=appstoreconnect-v1, ES256, short expiry (max 20 minutes).
    let now = Int(Date().timeIntervalSince1970)
    let exp = now + (15 * 60)

    let header: [String: Any] = [
        "alg": "ES256",
        "kid": keyID,
        "typ": "JWT",
    ]
    let payload: [String: Any] = [
        "iss": issuer,
        "iat": now,
        "exp": exp,
        "aud": "appstoreconnect-v1",
    ]

    let headerData = try JSONSerialization.data(withJSONObject: header)
    let payloadData = try JSONSerialization.data(withJSONObject: payload)

    let headerPart = base64url(headerData)
    let payloadPart = base64url(payloadData)
    let signingInput = "\(headerPart).\(payloadPart)"

    let key = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
    let signature = try key.signature(for: Data(signingInput.utf8))

    // JWS for ECDSA uses the raw (r||s) signature format, not DER.
    return "\(signingInput).\(base64url(signature.rawRepresentation))"
}

private func extractDataArray(_ obj: Any) -> [[String: Any]] {
    guard let dict = obj as? [String: Any], let data = dict["data"] as? [[String: Any]] else { return [] }
    return data
}

private func extractProductRows(_ obj: Any, kind: String) -> [(id: String, name: String?, state: String?)] {
    let rows = extractDataArray(obj)
    return rows.compactMap { entry in
        guard let attributes = entry["attributes"] as? [String: Any] else { return nil }

        // The API uses `productId` across IAPs and subscriptions.
        let id = (attributes["productId"] as? String)
            ?? (attributes["productID"] as? String)
            ?? ""
        guard !id.isEmpty else { return nil }

        let name = attributes["name"] as? String
            ?? attributes["referenceName"] as? String
        let state = attributes["state"] as? String
            ?? attributes["status"] as? String

        return (id: id, name: name.map { "\(kind): \($0)" }, state: state)
    }
}

private func parseBillingIdentifiers(repoRoot: URL) throws -> [String] {
    let billingPath = "OpenIntelligence/Services/Billing/BillingProduct.swift"
    let billingURL = URL(fileURLWithPath: billingPath, relativeTo: repoRoot)
    let billingSource = try String(contentsOf: billingURL, encoding: .utf8)

    // Matches: case foo = "product_id"
    let pattern = #"case\s+\w+\s*=\s*\"([A-Za-z0-9_\.]+)\""#
    let regex = try NSRegularExpression(pattern: pattern)

    let range = NSRange(billingSource.startIndex ..< billingSource.endIndex, in: billingSource)
    var ids = Set<String>()
    regex.enumerateMatches(in: billingSource, range: range) { match, _, _ in
        guard let match, match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: billingSource) else { return }
        ids.insert(String(billingSource[r]))
    }
    return ids.sorted()
}

private struct ASCClient {
    let token: String

    func requestJSON(path: String, queryItems: [URLQueryItem] = []) async throws -> Any {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.appstoreconnect.apple.com"
        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw CLIError.badURL("https://api.appstoreconnect.apple.com\(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIError.requestFailed("Request failed: no HTTPURLResponse")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(non-utf8 body)"
            throw CLIError.requestFailed("ASC HTTP \(http.statusCode) for \(url.absoluteString)\n\(body)")
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CLIError.decodeFailed("\(error)")
        }
    }
}

private func run() async throws {
    let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let dotenv = loadDotEnvIfPresent(repoRoot: repoRoot)

    let issuer = try configRequired("APP_STORE_CONNECT_ISSUER", dotenv: dotenv)
    let keyID = try configRequired("APP_STORE_CONNECT_KEY_ID", dotenv: dotenv)
    let keyPath = try configRequired("APP_STORE_CONNECT_PRIVATE_KEY_PATH", dotenv: dotenv)
    let bundleId = configOptional("APP_STORE_CONNECT_BUNDLE_ID", default: "Gunndamental.OpenIntelligence", dotenv: dotenv)

    // Allow either absolute paths or paths relative to repo root.
    let keyURL = URL(fileURLWithPath: keyPath, relativeTo: repoRoot).standardizedFileURL
    let privateKeyPEM = try String(contentsOf: keyURL, encoding: .utf8)
    guard !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CLIError.fileUnreadable(keyPath)
    }

    let token = try makeASCJWT(issuer: issuer, keyID: keyID, privateKeyPEM: privateKeyPEM)
    let client = ASCClient(token: token)

    let expectedIDs = try parseBillingIdentifiers(repoRoot: repoRoot)

    print("App Store Connect product check")
    print("  bundleId: \(bundleId)")
    print("  expected product IDs (from BillingProduct.swift): \(expectedIDs.joined(separator: ", "))")
    print("")

    // 1) Resolve app id from bundle id
    let appsObj = try await client.requestJSON(
        path: "/v1/apps",
        queryItems: [URLQueryItem(name: "filter[bundleId]", value: bundleId)]
    )
    let apps = extractDataArray(appsObj)
    guard let appId = apps.first?["id"] as? String else {
        throw CLIError.appNotFound(bundleId)
    }

    // 2) Query one-time / consumable IAPs
    let iapObj = try await client.requestJSON(
        path: "/v1/apps/\(appId)/inAppPurchasesV2",
        queryItems: [URLQueryItem(name: "limit", value: "200")]
    )
    let iapRows = extractProductRows(iapObj, kind: "IAP")

    // 3) Query subscriptions via groups -> subscriptions
    let groupsObj = try await client.requestJSON(
        path: "/v1/apps/\(appId)/subscriptionGroups",
        queryItems: [URLQueryItem(name: "limit", value: "200")]
    )
    let groups = extractDataArray(groupsObj)
    var subRows: [(id: String, name: String?, state: String?)] = []
    for group in groups {
        guard let groupId = group["id"] as? String else { continue }
        let subsObj = try await client.requestJSON(
            path: "/v1/subscriptionGroups/\(groupId)/subscriptions",
            queryItems: [URLQueryItem(name: "limit", value: "200")]
        )
        subRows.append(contentsOf: extractProductRows(subsObj, kind: "SUB"))
    }

    let ascIDs = Set(iapRows.map(\.id) + subRows.map(\.id))

    print("✅ App Store Connect returned \(ascIDs.count) total products")
    if !iapRows.isEmpty {
        print("\nIAPs:")
        for row in iapRows.sorted(by: { $0.id < $1.id }) {
            let details = [row.name, row.state].compactMap { $0 }.joined(separator: " • ")
            print("  - \(row.id)\(details.isEmpty ? "" : " (\(details))")")
        }
    }
    if !subRows.isEmpty {
        print("\nSubscriptions:")
        for row in subRows.sorted(by: { $0.id < $1.id }) {
            let details = [row.name, row.state].compactMap { $0 }.joined(separator: " • ")
            print("  - \(row.id)\(details.isEmpty ? "" : " (\(details))")")
        }
    }

    let missing = expectedIDs.filter { !ascIDs.contains($0) }
    if missing.isEmpty {
        print("\n✅ All BillingProduct identifiers are present in App Store Connect")
        return
    }

    print("\n❌ Missing in App Store Connect (or not visible via API):")
    for id in missing {
        print("  - \(id)")
    }
    throw CLIError.requestFailed("One or more BillingProduct identifiers were not found in ASC.")
}

Task {
    do {
        try await run()
        exit(0)
    } catch {
        fputs("❌ \(error)\n", stderr)
        fputs("\nTip: set env vars in your shell OR fill them in a local .env file in the repo root.\n", stderr)
        exit(1)
    }
}

dispatchMain()
