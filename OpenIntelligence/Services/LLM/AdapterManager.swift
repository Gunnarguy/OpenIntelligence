//
//  AdapterManager.swift
//  OpenIntelligence
//
//  Adapter Manager — Domain-Specific LoRA Adapter Lifecycle
//
//  Manages custom LoRA adapters for the Apple Foundation Model that specialize
//  on-device LLM responses for domain-specific document types (technical manuals,
//  medical records, legal documents, etc.).
//
//  ## Architecture
//
//  Adapters are ~160MB LoRA files (.fmadapter) trained via Apple's Python toolkit:
//    1. Server-side: Python `fmutil` trains adapter from curated domain datasets
//    2. Client-side: This service downloads, validates, and manages adapter lifecycle
//    3. Usage: LanguageModelSession(adapter:) applies domain specialization
//
//  ## Adapter Lifecycle
//
//    discover → download → validate → register → activate → (session uses it)
//
//  ## Storage
//
//    ~/Library/Application Support/OpenIntelligence/Adapters/
//      ├── medical.fmadapter
//      ├── technical.fmadapter
//      ├── legal.fmadapter
//      └── manifest.json  (registry of installed adapters)
//

import Combine
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Adapter Metadata

/// Describes a domain-specific LoRA adapter
struct AdapterDescriptor: Codable, Identifiable, Sendable {
    let id: String                  // e.g., "technical-v1", "medical-v2"
    let displayName: String         // e.g., "Technical Manuals"
    let domain: AdapterDomain       // Categorized domain
    let version: String             // Semantic version
    let minimumOSVersion: String    // e.g., "26.0"
    let fileSizeBytes: Int64        // Expected size for validation
    let sha256: String              // Integrity check
    let downloadURL: URL?           // Remote source (nil = bundled)
    let description: String         // User-facing description
    let trainedDate: Date           // When the adapter was trained
    let keywords: [String]          // Domain keywords for auto-selection
}

/// Supported adapter domains
enum AdapterDomain: String, Codable, Sendable, CaseIterable {
    case technical      // Manuals, specifications, engineering docs
    case medical        // Clinical notes, medical literature
    case legal          // Contracts, regulations, case law
    case financial      // Reports, filings, statements
    case scientific     // Research papers, lab reports
    case educational    // Textbooks, curricula
    case general        // General-purpose enhancement
}

/// Adapter installation state
enum AdapterState: String, Codable, Sendable {
    case available      // Known but not downloaded
    case downloading    // Download in progress
    case validating     // Checking integrity
    case installed      // Ready to use
    case active         // Currently loaded in memory
    case failed         // Installation failed
}

/// Installed adapter record
struct InstalledAdapter: Codable, Identifiable, Sendable {
    let id: String
    let descriptor: AdapterDescriptor
    var state: AdapterState
    let installedDate: Date
    var lastUsedDate: Date?
    var usageCount: Int
    var localPath: String           // Relative to adapters directory
}

// MARK: - Adapter Manager

/// Manages the lifecycle of domain-specific LoRA adapters for Apple Foundation Models.
/// Handles discovery, download, validation, registration, and activation.
@MainActor
final class AdapterManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AdapterManager()

    // MARK: - Published State

    @Published private(set) var installedAdapters: [InstalledAdapter] = []
    @Published private(set) var activeAdapterId: String?
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0

    // MARK: - Storage

    private let adaptersDirectory: URL
    private let manifestURL: URL
    private let fileManager = FileManager.default

    // MARK: - Initialization

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        self.adaptersDirectory = appSupport
            .appendingPathComponent("OpenIntelligence", isDirectory: true)
            .appendingPathComponent("Adapters", isDirectory: true)
        self.manifestURL = adaptersDirectory.appendingPathComponent("manifest.json")

        // Ensure directory exists
        try? fileManager.createDirectory(at: adaptersDirectory, withIntermediateDirectories: true)

        // Load manifest
        loadManifest()

        Log.info("[AdapterManager] Initialized with \(installedAdapters.count) adapters", category: .initialization)
    }

    // MARK: - Manifest Persistence

    private func loadManifest() {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }
        do {
            let data = try Data(contentsOf: manifestURL)
            installedAdapters = try JSONDecoder().decode([InstalledAdapter].self, from: data)

            // Validate file existence
            installedAdapters = installedAdapters.map { adapter in
                var a = adapter
                let fullPath = adaptersDirectory.appendingPathComponent(a.localPath)
                if !fileManager.fileExists(atPath: fullPath.path) {
                    a.state = .available
                }
                return a
            }
        } catch {
            Log.error("[AdapterManager] Failed to load manifest: \(error)", category: .initialization)
        }
    }

    private func saveManifest() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(installedAdapters)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            Log.error("[AdapterManager] Failed to save manifest: \(error)", category: .initialization)
        }
    }

    // MARK: - Adapter Discovery

    /// Get available adapters from the built-in catalog
    func availableAdapters() -> [AdapterDescriptor] {
        // Built-in adapter catalog — expanded as adapters are trained
        return [
            AdapterDescriptor(
                id: "technical-v1",
                displayName: "Technical Manuals",
                domain: .technical,
                version: "1.0.0",
                minimumOSVersion: "26.0",
                fileSizeBytes: 167_772_160,  // ~160MB
                sha256: "",  // Set after training
                downloadURL: nil,
                description: "Specialized for automotive manuals, engineering specifications, and technical documentation. Improves extraction of specs, procedures, and part numbers.",
                trainedDate: Date(),
                keywords: ["manual", "specification", "procedure", "torque", "PSI", "OHM", "VDC"]
            ),
            AdapterDescriptor(
                id: "medical-v1",
                displayName: "Medical Documents",
                domain: .medical,
                version: "1.0.0",
                minimumOSVersion: "26.0",
                fileSizeBytes: 167_772_160,
                sha256: "",
                downloadURL: nil,
                description: "Specialized for clinical notes, medical literature, and patient records. Improves medical terminology handling and clinical reasoning.",
                trainedDate: Date(),
                keywords: ["diagnosis", "treatment", "medication", "patient", "clinical", "ICD", "CPT"]
            ),
            AdapterDescriptor(
                id: "legal-v1",
                displayName: "Legal Documents",
                domain: .legal,
                version: "1.0.0",
                minimumOSVersion: "26.0",
                fileSizeBytes: 167_772_160,
                sha256: "",
                downloadURL: nil,
                description: "Specialized for contracts, regulations, and legal filings. Improves clause extraction, citation handling, and legal reasoning.",
                trainedDate: Date(),
                keywords: ["clause", "section", "hereby", "whereas", "plaintiff", "defendant", "statute"]
            )
        ]
    }

    /// Suggest the best adapter for a given document based on content analysis
    func suggestAdapter(forContent content: String) -> AdapterDomain? {
        let lowered = content.lowercased()
        let domainScores: [(AdapterDomain, Int)] = AdapterDomain.allCases.map { domain in
            let keywords = keywordsForDomain(domain)
            let score = keywords.reduce(0) { count, keyword in
                count + (lowered.contains(keyword) ? 1 : 0)
            }
            return (domain, score)
        }

        guard let best = domainScores.max(by: { $0.1 < $1.1 }), best.1 >= 3 else {
            return nil  // No strong domain signal
        }

        return best.0
    }

    private func keywordsForDomain(_ domain: AdapterDomain) -> [String] {
        switch domain {
        case .technical:
            return ["specification", "torque", "procedure", "maintenance", "assembly", "diagram", "voltage", "pressure", "tolerance"]
        case .medical:
            return ["patient", "diagnosis", "treatment", "medication", "symptoms", "clinical", "hemoglobin", "prescription", "dosage"]
        case .legal:
            return ["whereas", "hereby", "plaintiff", "defendant", "clause", "statute", "jurisdiction", "liability", "indemnify"]
        case .financial:
            return ["revenue", "earnings", "balance sheet", "fiscal", "dividend", "equity", "depreciation", "amortization", "EBITDA"]
        case .scientific:
            return ["hypothesis", "methodology", "results", "abstract", "peer-reviewed", "experiment", "statistical", "p-value", "control group"]
        case .educational:
            return ["chapter", "learning objectives", "quiz", "curriculum", "syllabus", "assignment", "textbook", "lesson", "module"]
        case .general:
            return []
        }
    }

    // MARK: - Adapter Installation

    /// Install an adapter from its descriptor
    func installAdapter(_ descriptor: AdapterDescriptor) async throws {
        guard !installedAdapters.contains(where: { $0.id == descriptor.id && $0.state == .installed }) else {
            Log.info("[AdapterManager] Adapter \(descriptor.id) already installed", category: .initialization)
            return
        }

        // Create or update record
        var adapter = InstalledAdapter(
            id: descriptor.id,
            descriptor: descriptor,
            state: .downloading,
            installedDate: Date(),
            lastUsedDate: nil,
            usageCount: 0,
            localPath: "\(descriptor.id).fmadapter"
        )

        if let idx = installedAdapters.firstIndex(where: { $0.id == descriptor.id }) {
            installedAdapters[idx] = adapter
        } else {
            installedAdapters.append(adapter)
        }
        saveManifest()

        // Download if remote
        if let url = descriptor.downloadURL {
            isDownloading = true
            downloadProgress = 0
            DSHaptics.processingPulse()
            HardwareTelemetryState.shared.sustain(.dataDecoding, active: true, intensity: 0.7)

            do {
                let localURL = adaptersDirectory.appendingPathComponent(adapter.localPath)
                let (tempURL, _) = try await URLSession.shared.download(from: url)
                try fileManager.moveItem(at: tempURL, to: localURL)

                downloadProgress = 1.0
                isDownloading = false
                HardwareTelemetryState.shared.sustain(.dataDecoding, active: false)
            } catch {
                adapter.state = .failed
                updateAdapter(adapter)
                isDownloading = false
                HardwareTelemetryState.shared.sustain(.dataDecoding, active: false)
                throw error
            }
        }

        // Validate
        adapter.state = .validating
        updateAdapter(adapter)

        let localPath = adaptersDirectory.appendingPathComponent(adapter.localPath)
        if fileManager.fileExists(atPath: localPath.path) {
            // Verify file size if specified
            if descriptor.fileSizeBytes > 0 {
                let attrs = try fileManager.attributesOfItem(atPath: localPath.path)
                let fileSize = attrs[.size] as? Int64 ?? 0
                if fileSize != descriptor.fileSizeBytes {
                    Log.warning("[AdapterManager] Size mismatch for \(descriptor.id): \(fileSize) vs expected \(descriptor.fileSizeBytes)", category: .initialization)
                }
            }
        }

        adapter.state = .installed
        updateAdapter(adapter)
        DSHaptics.success()
        Log.info("[AdapterManager] ✓ Adapter \(descriptor.id) installed", category: .initialization)
    }

    /// Remove an installed adapter
    func removeAdapter(id: String) throws {
        guard let idx = installedAdapters.firstIndex(where: { $0.id == id }) else { return }

        if activeAdapterId == id {
            deactivateAdapter()
        }

        let localPath = adaptersDirectory.appendingPathComponent(installedAdapters[idx].localPath)
        try? fileManager.removeItem(at: localPath)

        installedAdapters.remove(at: idx)
        saveManifest()

        Log.info("[AdapterManager] Adapter \(id) removed", category: .initialization)
    }

    // MARK: - Adapter Activation

    /// Activate an adapter for use in LLM sessions
    func activateAdapter(id: String) {
        guard let idx = installedAdapters.firstIndex(where: { $0.id == id && $0.state == .installed }) else {
            Log.warning("[AdapterManager] Cannot activate \(id) — not installed", category: .initialization)
            return
        }

        // Deactivate current
        if let currentId = activeAdapterId,
           let currentIdx = installedAdapters.firstIndex(where: { $0.id == currentId }) {
            installedAdapters[currentIdx].state = .installed
        }

        installedAdapters[idx].state = .active
        installedAdapters[idx].lastUsedDate = Date()
        installedAdapters[idx].usageCount += 1
        activeAdapterId = id
        saveManifest()

        DSHaptics.medium()
        HardwareTelemetryState.shared.pulse(.llmInference, intensity: 0.7, duration: 0.3)
        Log.info("[AdapterManager] ✓ Adapter \(id) activated", category: .initialization)
    }

    /// Deactivate the current adapter
    func deactivateAdapter() {
        if let currentId = activeAdapterId,
           let idx = installedAdapters.firstIndex(where: { $0.id == currentId }) {
            installedAdapters[idx].state = .installed
        }
        activeAdapterId = nil
        saveManifest()
    }

    /// Get the URL of the currently active adapter (for LanguageModelSession)
    func activeAdapterURL() -> URL? {
        guard let id = activeAdapterId,
              let adapter = installedAdapters.first(where: { $0.id == id }) else {
            return nil
        }
        return adaptersDirectory.appendingPathComponent(adapter.localPath)
    }

    // MARK: - Storage Management

    /// Total disk space used by installed adapters
    var totalDiskUsage: Int64 {
        installedAdapters.reduce(0) { total, adapter in
            let path = adaptersDirectory.appendingPathComponent(adapter.localPath)
            let attrs = try? fileManager.attributesOfItem(atPath: path.path)
            return total + (attrs?[.size] as? Int64 ?? 0)
        }
    }

    /// Clean up failed or orphaned adapter files
    func cleanup() throws {
        let contents = try fileManager.contentsOfDirectory(at: adaptersDirectory, includingPropertiesForKeys: nil)
        let knownPaths = Set(installedAdapters.map { adaptersDirectory.appendingPathComponent($0.localPath).path })

        for url in contents where url.lastPathComponent != "manifest.json" {
            if !knownPaths.contains(url.path) {
                try? fileManager.removeItem(at: url)
                Log.info("[AdapterManager] Cleaned up orphaned file: \(url.lastPathComponent)", category: .initialization)
            }
        }
    }

    // MARK: - Private Helpers

    private func updateAdapter(_ adapter: InstalledAdapter) {
        if let idx = installedAdapters.firstIndex(where: { $0.id == adapter.id }) {
            installedAdapters[idx] = adapter
        }
        saveManifest()
    }
}
