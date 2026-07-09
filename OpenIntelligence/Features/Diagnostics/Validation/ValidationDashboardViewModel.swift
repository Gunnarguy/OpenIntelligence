#if DEBUG
import Foundation
import SwiftUI
import Combine

@MainActor
class ValidationDashboardViewModel: ObservableObject {
    struct Manifest: Codable {
        let version: Int
        let name: String
        let cases: [TestCase]
    }
    
    struct TestCase: Codable {
        let id: String
        let input_files: [String]
        let query: String
        let quality_mode: String
    }
    
    @Published var isRunning = false
    @Published var outputText = ""
    @Published var selectedFileURL: URL?
    
    let ragService: RAGService
    let settingsStore: SettingsStore
    
    init(ragService: RAGService, settingsStore: SettingsStore) {
        self.ragService = ragService
        self.settingsStore = settingsStore
        if let lastReport = DebugRAGValidationHarness.lastReport {
            self.outputText = lastReport
        }
    }
    
    func loadAndRunSuite(from url: URL) {
        guard !isRunning else { return }
        
        // Ensure we have access to the selected file URL
        guard url.startAccessingSecurityScopedResource() else {
            outputText = "Error: Could not access file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        selectedFileURL = url
        outputText = "Loading manifest: \(url.lastPathComponent)...\n"
        
        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            
            outputText += "Found \(manifest.cases.count) test cases.\n\n"
            runSuite(manifest: manifest, baseURL: url.deletingLastPathComponent())
        } catch {
            outputText += "Error parsing manifest: \(error.localizedDescription)\n"
            
            // If it's not a JSON manifest, maybe it's just a document, but let's assume manifest for the suite runner.
            // For single files, they should use a separate method or we can fallback to a single document test.
            self.outputText += "Try running as a single document query instead."
        }
    }
    
    private func runSuite(manifest: Manifest, baseURL: URL) {
        isRunning = true
        
        Task.detached {
            for testCase in manifest.cases {
                await MainActor.run {
                    self.outputText += "========================================\n"
                    self.outputText += "Executing: \(testCase.id)\n"
                }
                
                // Resolve input file URLs relative to the manifest, or try relative to project root (since scripts used repo root)
                // The python script assumed repo root for paths like "Benchmarks/Fixtures/..."
                // For a native Mac app, the easiest is to resolve relative to the manifest directory if they are bundled together.
                // However, "Benchmarks/Fixtures/..." inside the app sandbox won't exist unless it's in the bundle.
                // If the user selected a manifest in their workspace, we'll try to resolve relative to the workspace root.
                // Let's just create absolute URLs assuming the JSON path is relative to the repo root, 
                // but since we are running in the app sandbox, we might not have access to those files unless they are bundled.
                // For now, let's just attempt to resolve relative to the manifest URL.
                let inputURLs: [URL] = testCase.input_files.map { path in
                    // Assume the path might contain "Benchmarks/...", let's just use it relative to the manifest dir for now
                    // Or if it's an absolute path, use it.
                    if path.hasPrefix("/") {
                        return URL(fileURLWithPath: path)
                    } else {
                        // The user's repo paths are like "Benchmarks/Fixtures/..."
                        // If the manifest is at `.../Benchmarks/rag_validation_sample.json`, 
                        // then we need to go up one level.
                        let repoRoot = baseURL.deletingLastPathComponent()
                        return repoRoot.appendingPathComponent(path)
                    }
                }
                
                let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("OpenIntelligenceRAGBenchmark/visual-run/\(testCase.id)/storage")
                let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("OpenIntelligenceRAGBenchmark/visual-run/\(testCase.id)/output")
                
                var mode: RAGQualityMode = .standard
                if testCase.quality_mode.lowercased() == "deep-think" || testCase.quality_mode.lowercased() == "deepthink" {
                    mode = .deepThink
                } else if testCase.quality_mode.lowercased() == "maximum" {
                    mode = .maximum
                }
                
                let config = DebugRAGValidationHarness.Configuration(
                    query: testCase.query,
                    inputURLs: inputURLs,
                    storageDirectory: storageURL,
                    outputDirectory: outputURL,
                    qualityMode: mode,
                    shouldIngest: true,
                    pccConsent: "allow",
                    benchmarkEntitlement: .pro
                )
                
                do {
                    let report = try await DebugRAGValidationHarness.run(
                        configuration: config,
                        ragService: self.ragService,
                        settingsStore: self.settingsStore
                    )
                    await MainActor.run {
                        self.outputText += "\(report)\n\n"
                    }
                } catch {
                    let errorReport = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String
                    await MainActor.run {
                        if let errorReport = errorReport {
                            self.outputText += "Error:\n\(errorReport)\n\n"
                        } else {
                            self.outputText += "Error: \(error.localizedDescription)\n\n"
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.outputText += "Suite Finished.\n"
                self.isRunning = false
            }
        }
    }
    
    func runSingleDocument(url: URL, query: String, qualityMode: RAGQualityMode) {
        guard !isRunning else { return }
        
        guard url.startAccessingSecurityScopedResource() else {
            outputText = "Error: Could not access document file."
            return
        }
        
        isRunning = true
        selectedFileURL = url
        outputText = "Starting single benchmark for \(url.lastPathComponent)...\n"
        
        Task.detached {
            // Need to keep the security scope active during execution
            defer { url.stopAccessingSecurityScopedResource() }
            
            let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("OpenIntelligenceRAGBenchmark/visual-run/storage")
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("OpenIntelligenceRAGBenchmark/visual-run/output")
            
            let config = DebugRAGValidationHarness.Configuration(
                query: query,
                inputURLs: [url],
                storageDirectory: storageURL,
                outputDirectory: outputURL,
                qualityMode: qualityMode,
                shouldIngest: true,
                pccConsent: "allow",
                benchmarkEntitlement: .pro
            )
            
            do {
                let report = try await DebugRAGValidationHarness.run(
                    configuration: config,
                    ragService: self.ragService,
                    settingsStore: self.settingsStore
                )
                await MainActor.run {
                    self.outputText += "\n\(report)\n\nFinished Successfully."
                }
            } catch {
                let errorReport = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String
                await MainActor.run {
                    if let errorReport = errorReport {
                        self.outputText += "\nError:\n\(errorReport)"
                    } else {
                        self.outputText += "\nError: \(error.localizedDescription)"
                    }
                }
            }
            await MainActor.run {
                self.isRunning = false
            }
        }
    }
}
#endif
