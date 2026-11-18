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

    /// 2026-11-18: on the owner's Mac 59 of 73 tombstones shared one `discardedAt`, and their order
    /// came from dictionary iteration, so every sync pass wrote a reordered `ingestion_queue.json`.
    func testTombstonesThatTieOnDiscardedAtKeepOneOrder() {
        let tied = Date(timeIntervalSince1970: 1_700_000_000)
        let newest = IngestionQueueTombstone(id: UUID(), containerId: nil, discardedAt: tied.addingTimeInterval(60))
        let ties = (0..<40).map { _ in IngestionQueueTombstone(id: UUID(), containerId: nil, discardedAt: tied) }

        let forward = IngestionQueueTombstonePolicy.merged(ties, [newest])
        let backward = IngestionQueueTombstonePolicy.merged([newest], ties.reversed())
        let split = IngestionQueueTombstonePolicy.merged(Array(ties.suffix(20)), Array(ties.prefix(20)) + [newest])

        XCTAssertEqual(forward.map(\.id), backward.map(\.id))
        XCTAssertEqual(forward.map(\.id), split.map(\.id))
        XCTAssertEqual(forward.first?.id, newest.id, "newest first still holds")
        XCTAssertEqual(forward.dropFirst().map(\.id.uuidString), ties.map(\.id.uuidString).sorted(), "ties go by id")
    }

    func testTheTombstonesKeptPastTheCapDoNotDependOnInputOrder() {
        let tied = Date(timeIntervalSince1970: 1_700_000_000)
        let ties = (0..<(IngestionQueueTombstonePolicy.maximumRetainedTombstones + 20)).map { _ in
            IngestionQueueTombstone(id: UUID(), containerId: nil, discardedAt: tied)
        }

        let forward = IngestionQueueTombstonePolicy.merged(ties, [])
        let backward = IngestionQueueTombstonePolicy.merged([], ties.reversed())

        let expected = Array(
            ties.map(\.id.uuidString).sorted().prefix(IngestionQueueTombstonePolicy.maximumRetainedTombstones))
        XCTAssertEqual(forward.map(\.id.uuidString), expected, "the lowest ids are kept, in id order")
        XCTAssertEqual(backward.map(\.id.uuidString), expected)
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }
}
