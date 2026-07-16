import XCTest
@testable import OpenIntelligence

final class IngestionQueueTombstoneTests: XCTestCase {
    func testLegacyQueueStateDecodesWithoutTombstones() throws {
        let item = IngestionItem(url: URL(fileURLWithPath: "/tmp/legacy.pdf"))
        let legacyPayload: [String: Any] = [
            "items": try jsonObject([item]),
            "contexts": [],
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyPayload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(PersistedIngestionQueueStateRecord.self, from: data)

        XCTAssertEqual(decoded.items.map(\.id), [item.id])
        XCTAssertTrue(decoded.tombstones.isEmpty)
    }

    func testTombstoneRemovesMatchingRestoredItem() {
        let discarded = IngestionItem(url: URL(fileURLWithPath: "/tmp/discarded.pdf"))
        let replacement = IngestionItem(url: URL(fileURLWithPath: "/tmp/discarded.pdf"))
        let tombstone = IngestionQueueTombstone(
            id: discarded.id,
            containerId: discarded.containerId
        )

        let remaining = IngestionQueueTombstonePolicy.removingTombstonedItems(
            [discarded, replacement],
            tombstones: [tombstone]
        )

        XCTAssertEqual(remaining.map(\.id), [replacement.id], "A later explicit import uses a new ID and remains allowed.")
    }

    func testTombstoneMergeUsesNewestValueAndStaysBounded() {
        let sharedID = UUID()
        let older = IngestionQueueTombstone(
            id: sharedID,
            containerId: nil,
            discardedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = IngestionQueueTombstone(
            id: sharedID,
            containerId: UUID(),
            discardedAt: Date(timeIntervalSince1970: 10_000)
        )
        let extras = (0...IngestionQueueTombstonePolicy.maximumRetainedTombstones).map { offset in
            IngestionQueueTombstone(
                id: UUID(),
                containerId: nil,
                discardedAt: Date(timeIntervalSince1970: TimeInterval(10 + offset))
            )
        }

        let merged = IngestionQueueTombstonePolicy.merged([older], [newer] + extras)

        XCTAssertEqual(merged.count, IngestionQueueTombstonePolicy.maximumRetainedTombstones)
        XCTAssertEqual(merged.first(where: { $0.id == sharedID }), newer)
        XCTAssertEqual(merged.map(\.discardedAt), merged.map(\.discardedAt).sorted(by: >))
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }
}
