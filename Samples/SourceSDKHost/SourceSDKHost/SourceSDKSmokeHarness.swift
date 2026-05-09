import Foundation
import OpenIntelligenceEngine
import SwiftUI

enum SourceSDKHostRuntime {
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    static let isRunningSmokeHarness = ProcessInfo.processInfo.environment["SOURCE_SDK_SMOKE_TEST_MODE"] == "1"

    static var shouldSkipInteractiveBootstrap: Bool {
        isRunningTests || isRunningSmokeHarness
    }

    static func smokeResultURL(fileManager: FileManager = .default) -> URL? {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        return cachesDirectory.appendingPathComponent("source-sdk-smoke-result.json")
    }
}

private struct SourceSDKSmokeCheck: Codable {
    let name: String
    let status: String
    let detail: String
}

private struct SourceSDKSmokeResult: Codable {
    let success: Bool
    let message: String
    let checks: [SourceSDKSmokeCheck]
    let generatedAt: Date
}

private struct SourceSDKSmokeHarnessError: LocalizedError {
    let errorDescription: String?

    init(_ description: String) {
        errorDescription = description
    }
}

@MainActor
final class SourceSDKSmokeHarness: ObservableObject {
    @Published private(set) var status = "Preparing simulator smoke checks..."

    private var didRun = false
    private let fileManager = FileManager.default

    func runIfNeeded() async {
        guard !didRun else { return }
        didRun = true

        let result = await execute()
        status = result.message
        persist(result)
    }

    private func execute() async -> SourceSDKSmokeResult {
        var checks: [SourceSDKSmokeCheck] = []

        do {
            checks.append(.init(name: "Availability", status: "passed", detail: try checkAvailability()))
            checks.append(.init(name: "Blank Library", status: "passed", detail: try checkBlankLibraryRejection()))
            checks.append(.init(name: "Library Lifecycle", status: "passed", detail: try checkLibraryLifecycle()))
            checks.append(.init(name: "Empty Ingest", status: "passed", detail: try await checkEmptyIngestRejection()))
            checks.append(.init(name: "Simulator Query", status: "passed", detail: try await checkSimulatorQueryUnavailable()))

            return SourceSDKSmokeResult(
                success: true,
                message: "Source SDK smoke harness completed 5 checks successfully.",
                checks: checks,
                generatedAt: Date()
            )
        } catch {
            checks.append(
                .init(
                    name: "Failure",
                    status: "failed",
                    detail: error.localizedDescription
                )
            )

            return SourceSDKSmokeResult(
                success: false,
                message: "Source SDK smoke harness failed: \(error.localizedDescription)",
                checks: checks,
                generatedAt: Date()
            )
        }
    }

    private func checkAvailability() throws -> String {
        let availability = OIEngine.availability()
        guard availability == .simulatorUnsupported else {
            throw SourceSDKSmokeHarnessError(
                "Expected simulatorUnsupported availability, got \(describeAvailability(availability))."
            )
        }

        return "Availability returned simulatorUnsupported."
    }

    private func checkBlankLibraryRejection() throws -> String {
        let (engine, storageURL) = try makeEngine()
        defer { cleanupStorage(at: storageURL) }

        do {
            _ = try engine.createLibrary(name: "   ")
            throw SourceSDKSmokeHarnessError("Expected blank library creation to throw invalidRequest.")
        } catch let OpenIntelligenceEngineError.invalidRequest(message) {
            guard message.contains("must not be empty") else {
                throw SourceSDKSmokeHarnessError("Unexpected blank library error message: \(message)")
            }

            return "Blank library names are rejected with invalidRequest."
        } catch {
            throw SourceSDKSmokeHarnessError("Unexpected blank library error: \(error.localizedDescription)")
        }
    }

    private func checkLibraryLifecycle() throws -> String {
        let (engine, storageURL) = try makeEngine()
        defer { cleanupStorage(at: storageURL) }

        let libraryName = "Smoke Library \(UUID().uuidString)"
        let created = try engine.createLibrary(name: libraryName)

        let afterCreate = engine.listLibraries()
        guard afterCreate.contains(where: { $0.id == created.id && $0.name == libraryName }) else {
            throw SourceSDKSmokeHarnessError("Created library was missing from listLibraries().")
        }

        try engine.deleteLibrary(id: created.id)
        let afterDelete = engine.listLibraries()
        guard !afterDelete.contains(where: { $0.id == created.id }) else {
            throw SourceSDKSmokeHarnessError("Deleted library still appeared in listLibraries().")
        }

        return "Library CRUD completed successfully."
    }

    private func checkEmptyIngestRejection() async throws -> String {
        let (engine, storageURL) = try makeEngine()
        defer { cleanupStorage(at: storageURL) }

        let library = try engine.createLibrary(name: "Ingest Smoke \(UUID().uuidString)")

        do {
            _ = try await engine.ingest(OIIngestRequest(urls: []), into: library.id)
            throw SourceSDKSmokeHarnessError("Expected empty ingest request to throw invalidRequest.")
        } catch let OpenIntelligenceEngineError.invalidRequest(message) {
            guard message.contains("At least one document URL is required") else {
                throw SourceSDKSmokeHarnessError("Unexpected empty ingest error message: \(message)")
            }

            return "Empty ingest requests are rejected before ingestion starts."
        } catch {
            throw SourceSDKSmokeHarnessError("Unexpected ingest error: \(error.localizedDescription)")
        }
    }

    private func checkSimulatorQueryUnavailable() async throws -> String {
        let (engine, storageURL) = try makeEngine()
        defer { cleanupStorage(at: storageURL) }

        let library = try engine.createLibrary(name: "Query Smoke \(UUID().uuidString)")

        do {
            _ = try await engine.query(OIQueryRequest(question: "What happened?"), in: library.id)
            throw SourceSDKSmokeHarnessError("Expected simulator query to throw unavailable.")
        } catch let OpenIntelligenceEngineError.unavailable(state) {
            guard state == .simulatorUnsupported else {
                throw SourceSDKSmokeHarnessError(
                    "Expected simulatorUnsupported query state, got \(describeAvailability(state))."
                )
            }

            return "Queries fail cleanly on simulator with simulatorUnsupported."
        } catch {
            throw SourceSDKSmokeHarnessError("Unexpected query error: \(error.localizedDescription)")
        }
    }

    private func makeEngine() throws -> (OIEngine, URL) {
        let storageURL = fileManager.temporaryDirectory
            .appendingPathComponent("SourceSDKSmokeHarness", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)

        let engine = OIEngine(
            configuration: OIEngineConfiguration(
                storageURL: storageURL,
                allowPrivateCloudCompute: false,
                executionContext: .onDeviceOnly
            )
        )

        return (engine, storageURL)
    }

    private func cleanupStorage(at url: URL) {
        try? fileManager.removeItem(at: url)
    }

    private func persist(_ result: SourceSDKSmokeResult) {
        guard let url = SourceSDKHostRuntime.smokeResultURL(fileManager: fileManager) else { return }

        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            try data.write(to: url, options: .atomic)
        } catch {
            status = "Failed to write smoke result: \(error.localizedDescription)"
        }
    }

    private func describeAvailability(_ availability: OIAvailabilityState) -> String {
        switch availability {
        case .available:
            return "available"
        case .simulatorUnsupported:
            return "simulatorUnsupported"
        case .unsupportedDevice:
            return "unsupportedDevice"
        case .appleIntelligenceDisabled:
            return "appleIntelligenceDisabled"
        case .modelPreparing:
            return "modelPreparing"
        case let .unavailable(message):
            return "unavailable(\(message))"
        }
    }
}

struct SourceSDKSmokeHarnessView: View {
    @StateObject private var harness = SourceSDKSmokeHarness()

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Running Source SDK smoke harness")
                .font(.headline)
            Text(harness.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .task {
            await harness.runIfNeeded()
        }
    }
}
