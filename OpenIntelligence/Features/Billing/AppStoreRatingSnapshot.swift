//
//  AppStoreRatingSnapshot.swift
//  OpenIntelligence
//
//  The app's own App Store rating, for the one line on the plans screen that is allowed to
//  cite it.
//
//  WHY THIS EXISTS
//
//  The plans screen carried a banner labelled "social proof" that contained none: it said
//  "Upgrade anytime, cancel in App Store settings." The two things a buyer can actually check
//  are the rating on the product page and the privacy label, so those are what the banner says
//  now. A hardcoded rating goes stale the week after it is typed, so this reads the real one.
//
//  WHY THE COUNT GATES IT
//
//  Published evidence on in-app social proof comes from apps with thousands of ratings and none
//  of it tests a count under 100. "4.8 from 5 ratings" tells a buyer the app is new, not that it
//  is good. So the rating line appears only once the count reaches `minimumRatingCount`; until
//  then the banner shows the privacy label alone, which is true at any count.
//
//  WHAT IT SENDS
//
//  One GET to Apple's public lookup endpoint with the app's own App Store id, at most once a day,
//  nothing about the user. That endpoint is the same one the App Store app reads. The app's
//  privacy label is Data Not Collected, and this keeps it so: no identifier, no query, no
//  document, nothing that names the device.
//

import Foundation

struct AppStoreRatingSnapshot: Codable, Equatable, Sendable {
    let average: Double
    let count: Int
    let fetchedAt: Date

    /// Below this, the line is withheld. See the header.
    static let minimumRatingCount = 20

    var isWorthShowing: Bool { count >= Self.minimumRatingCount && average > 0 }

    /// "4.8 on the App Store, 143 ratings". One decimal, because that is what the store shows.
    var line: String {
        let rounded = (average * 10).rounded() / 10
        return "\(rounded.formatted(.number.precision(.fractionLength(1)))) on the App Store, \(count) ratings"
    }
}

enum AppStoreRatingService {
    private static let cacheKey = "appStoreRating.snapshot"
    private static let maxAge: TimeInterval = 24 * 60 * 60

    /// Cached snapshot if one exists, fresh or not. The banner renders this synchronously so
    /// the sheet never waits on the network.
    static func cached(defaults: UserDefaults = .standard) -> AppStoreRatingSnapshot? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(AppStoreRatingSnapshot.self, from: data)
    }

    /// Refreshes at most once a day. Silent on any failure: offline, a changed payload, a
    /// throttled endpoint. The banner falls back to the privacy label, which needs no network.
    static func refreshIfStale(defaults: UserDefaults = .standard, now: Date = Date()) async {
        if let cached = cached(defaults: defaults), now.timeIntervalSince(cached.fetchedAt) < maxAge {
            return
        }
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(OpenIntelligenceLinks.appStoreID)") else {
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let snapshot = parse(data, now: now),
            let encoded = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(encoded, forKey: cacheKey)
    }

    /// Pure, so the payload shape is pinned by a test rather than discovered in production.
    static func parse(_ data: Data, now: Date) -> AppStoreRatingSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = object["results"] as? [[String: Any]],
            let first = results.first,
            let average = first["averageUserRating"] as? Double,
            let count = first["userRatingCount"] as? Int
        else { return nil }
        return AppStoreRatingSnapshot(average: average, count: count, fetchedAt: now)
    }
}
