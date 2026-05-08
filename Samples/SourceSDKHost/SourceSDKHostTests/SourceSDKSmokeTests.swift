import Foundation
import OpenIntelligenceEngine
import XCTest

@MainActor
final class SourceSDKSmokeTests: XCTestCase {
    func testAvailabilityReflectsSimulatorEnvironment() {
        XCTAssertEqual(OIEngine.availability(), .simulatorUnsupported)
    }

    func testCreateLibraryRejectsBlankName() throws {
        let engine = try makeEngine()

        XCTAssertThrowsError(try engine.createLibrary(name: "   ")) { error in
            guard case let OpenIntelligenceEngineError.invalidRequest(message) = error else {
                return XCTFail("Expected invalidRequest error, got \(error)")
            }

            XCTAssertTrue(message.contains("must not be empty"))
        }
    }

    func testLibraryLifecycleSupportsCreateListDelete() throws {
        let engine = try makeEngine()
        let libraryName = "Smoke Test \(UUID().uuidString)"

        let created = try engine.createLibrary(name: libraryName)
        let afterCreate = engine.listLibraries()

        XCTAssertTrue(afterCreate.contains(where: { $0.id == created.id && $0.name == libraryName }))

        try engine.deleteLibrary(id: created.id)
        let afterDelete = engine.listLibraries()

        XCTAssertFalse(afterDelete.contains(where: { $0.id == created.id }))
    }

    func testIngestRejectsEmptyURLList() async throws {
        let engine = try makeEngine()
        let library = try engine.createLibrary(name: "Ingest Smoke \(UUID().uuidString)")

        await XCTAssertThrowsErrorAsync(try await engine.ingest(OIIngestRequest(urls: []), into: library.id)) { error in
            guard case let OpenIntelligenceEngineError.invalidRequest(message) = error else {
                return XCTFail("Expected invalidRequest error, got \(error)")
            }

            XCTAssertTrue(message.contains("At least one document URL is required"))
        }
    }

    func testQueryFailsCleanlyOnSimulator() async throws {
        let engine = try makeEngine()
        let library = try engine.createLibrary(name: "Query Smoke \(UUID().uuidString)")

        await XCTAssertThrowsErrorAsync(try await engine.query(OIQueryRequest(question: "What happened?"), in: library.id)) { error in
            guard case let OpenIntelligenceEngineError.unavailable(state) = error else {
                return XCTFail("Expected unavailable error, got \(error)")
            }

            XCTAssertEqual(state, .simulatorUnsupported)
        }
    }

    private func makeEngine() throws -> OIEngine {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenIntelligenceEngine-SourceSDKSmokeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: storageURL)
        }

        return OIEngine(
            configuration: OIEngineConfiguration(
                storageURL: storageURL,
                allowPrivateCloudCompute: false,
                executionContext: .onDeviceOnly
            )
        )
    }

    private func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ errorHandler: (Error) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}