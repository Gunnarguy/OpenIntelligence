//
//  ModelDownloadService.swift
//  OpenIntelligence
//
//  Minimal model catalog + downloader (Phase 1)
//  - Fetch a manifest (JSON) of downloadable models
//  - Download large files with progress
//  - Move into Documents/Models
//  - Register in ModelRegistry (GGUF/CoreML)
//

import Combine
import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif

// MARK: - Hugging Face Support

struct HuggingFaceRef {
    let owner: String
    let repo: String
    let revision: String
    let path: String
}

extension ModelDownloadService {
    /// Parse hf://owner/repo[:revision]/path/to/file.gguf
    static func parseHFURL(_ s: String) -> HuggingFaceRef? {
        guard s.lowercased().hasPrefix("hf://") else { return nil }
        let trimmed = String(s.dropFirst("hf://".count))
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let owner = String(parts[0])
        let repoRev = String(parts[1])
        let path = parts.dropFirst(2).joined(separator: "/")
        let repo: String
        let rev: String
        if let idx = repoRev.firstIndex(of: ":") {
            repo = String(repoRev[..<idx])
            rev = String(repoRev[repoRev.index(after: idx)...])
        } else {
            repo = repoRev
            rev = "main"
        }
        guard !owner.isEmpty, !repo.isEmpty, !path.isEmpty else { return nil }
        return HuggingFaceRef(owner: owner, repo: repo, revision: rev, path: path)
    }

    /// Return a persisted Hugging Face token if present (Settings should write "hfToken")
    static func huggingFaceToken() -> String? {
        if let raw = UserDefaults.standard.string(forKey: "hfToken")?.trimmingCharacters(
            in: .whitespacesAndNewlines),
            !raw.isEmpty
        {
            return raw
        }
        return nil
    }

    /// Build a /resolve request that will 302 to the CDN; attach Authorization if token supplied
    static func huggingFaceResolveRequest(for ref: HuggingFaceRef, token: String?) -> URLRequest? {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "huggingface.co"
        comps.path = "/\(ref.owner)/\(ref.repo)/resolve/\(ref.revision)/\(ref.path)"
        comps.queryItems = [URLQueryItem(name: "download", value: "true")]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }
}

/// Minimal HF model info for listing files
struct HFModelInfo: Codable {
    let id: String
    let siblings: [HFSibling]?
}

struct HFSibling: Codable, Identifiable, Hashable {
    var id: String { rfilename }
    let rfilename: String
    let size: Int64?
    let lfs: HFLFSInfo?
}

struct HFLFSInfo: Codable, Hashable {
    let oid: String?
    let size: Int64?
    let sha256: String?
}

extension ModelDownloadService {
    /// List GGUF (and optionally .mlpackage/.zip) files from a Hugging Face repo
    func listHuggingFaceGGUFFiles(
        owner: String, repo: String, token: String?, includeCoreML: Bool = false
    ) async throws -> [HFSibling] {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "huggingface.co"
        comps.path = "/api/models/\(owner)/\(repo)"
        comps.queryItems = [URLQueryItem(name: "expand[]", value: "siblings")]
        guard let url = comps.url else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 403 {
                throw NSError(
                    domain: "HF", code: 403,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Access denied. If the model is gated, accept the license on huggingface.co and set a token in Settings."
                    ])
            }
            if http.statusCode == 404 {
                throw NSError(
                    domain: "HF", code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Repo not found: \(owner)/\(repo)"])
            }
            if http.statusCode == 429 {
                throw NSError(
                    domain: "HF", code: 429,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Rate limited by Hugging Face. Try again later."
                    ])
            }
            throw NSError(
                domain: "HF", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        let info = try JSONDecoder().decode(HFModelInfo.self, from: data)
        let files = info.siblings ?? []
        let filtered = files.filter { sib in
            let name = sib.rfilename.lowercased()
            if name.hasSuffix(".gguf") { return true }
            if includeCoreML
                && (name.hasSuffix(".mlpackage") || name.hasSuffix(".mlpackage.zip")
                    || name.hasSuffix(".zip"))
            {
                return true
            }
            return false
        }
        TelemetryCenter.emit(
            .system,
            title: "HF repo files listed",
            metadata: ["repo": "\(owner)/\(repo)", "count": "\(filtered.count)"]
        )
        return filtered
    }

    /// Convenience: create a temporary catalog entry for an HF file and start download
    func startHuggingFaceDownload(
        owner: String, repo: String, revision: String = "main", path: String, sizeBytes: Int64?,
        sha256: String?
    ) {
        let lower = path.lowercased()
        let backend: ModelBackend = {
            if lower.hasSuffix(".gguf") { return .gguf }
            if lower.hasSuffix(".mlpackage") || lower.hasSuffix(".mlpackage.zip")
                || lower.hasSuffix(".zip")
            {
                return .coreML
            }
            return .gguf
        }()
        let urlStr = "hf://\(owner)/\(repo):\(revision)/\(path)"
        let display = "\(repo) • \(path.split(separator: "/").last ?? Substring(path))"
        let entry = ModelCatalogEntry(
            name: String(display),
            backend: backend,
            url: urlStr,
            sizeBytes: sizeBytes,
            checksumSHA256: sha256,
            vendor: "Hugging Face",
            contextWindow: nil,
            quantization: nil,
            filename: String(path.split(separator: "/").last ?? Substring(path))
        )
        // Surface ad-hoc entry in the gallery for visibility
        self.catalog.insert(entry, at: 0)
        self.download(entry: entry)
        TelemetryCenter.emit(
            .system,
            title: "HF download started",
            metadata: ["repo": "\(owner)/\(repo)", "rev": revision, "path": path]
        )
    }
}

// MARK: - Catalog Data

struct ModelCatalogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let backend: ModelBackend
    let url: String
    let sizeBytes: Int64?
    let checksumSHA256: String?  // hex string; optional
    let vendor: String?
    let contextWindow: Int?
    let quantization: String?
    let filename: String?  // optional override for destination name

    init(
        id: UUID = UUID(),
        name: String,
        backend: ModelBackend,
        url: String,
        sizeBytes: Int64? = nil,
        checksumSHA256: String? = nil,
        vendor: String? = nil,
        contextWindow: Int? = nil,
        quantization: String? = nil,
        filename: String? = nil
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.url = url
        self.sizeBytes = sizeBytes
        self.checksumSHA256 = checksumSHA256
        self.vendor = vendor
        self.contextWindow = contextWindow
        self.quantization = quantization
        self.filename = filename
    }
}

struct ModelCatalogManifest: Codable {
    let updated: String
    let entries: [ModelCatalogEntry]
}

// MARK: - Download State

enum DownloadStatus: Equatable {
    case idle
    case downloading
    case paused
    case verifying
    case registering
    case completed(localURL: URL)
    case failed(error: String)
    case cancelled
}

struct DownloadState: Identifiable, Equatable {
    let id: UUID
    let entry: ModelCatalogEntry
    var progress: Double
    var status: DownloadStatus
    var bytesWritten: Int64
    var totalBytes: Int64
    var averageBytesPerSecond: Double?
    var lastTick: Date?

    init(entry: ModelCatalogEntry) {
        self.id = entry.id
        self.entry = entry
        self.progress = 0.0
        self.status = .idle
        self.bytesWritten = 0
        self.totalBytes = 0
        self.averageBytesPerSecond = nil
        self.lastTick = nil
    }
}

// MARK: - Service

@MainActor
final class ModelDownloadService: NSObject, ObservableObject {
    static let shared = ModelDownloadService()

    // Public data
    @Published private(set) var catalog: [ModelCatalogEntry] = []
    @Published private(set) var downloads: [UUID: DownloadState] = [:]
    @Published var isLoadingCatalog: Bool = false
    @Published var catalogError: String?

    // URLSession with delegate for progress callbacks
    private var session: URLSession

    private func buildSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        // Allow downloads over cellular - no WiFi-only restriction
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 60 * 60
        config.timeoutIntervalForResource = 60 * 60 * 6
        #if os(iOS)
            if #available(iOS 15.0, *) {
                if #available(iOS 18.4, *) {
                    // Deprecated as of iOS 18.4
                } else {
                    config.shouldUseExtendedBackgroundIdleMode = true
                }
            }
        #endif
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }

    // Map task identifiers to entry ids
    private var taskToEntry: [Int: UUID] = [:]
    // Resume data per entry for pause/resume
    private var resumeDataByEntry: [UUID: Data] = [:]
    // Track entries intentionally paused to distinguish from errors
    private var intentionallyPaused: Set<UUID> = []
    // Throttle progress telemetry events per entry
    private var lastProgressEventAt: [UUID: Date] = [:]

    private override init() {
        // Temporary session to satisfy initialization before super.init()
        self.session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        super.init()
        // Build configured background session
        self.session = buildSession()
    }

    // MARK: - Catalog

    func loadCatalog(from url: URL?) async {
        isLoadingCatalog = true
        catalogError = nil
        defer { isLoadingCatalog = false }

        if let url = url {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let manifest = try JSONDecoder().decode(ModelCatalogManifest.self, from: data)
                self.catalog = manifest.entries
                TelemetryCenter.emit(
                    .system,
                    title: "Model catalog loaded",
                    metadata: [
                        "source": url.absoluteString,
                        "count": "\(manifest.entries.count)",
                    ]
                )
                return
            } catch {
                self.catalogError = "Failed to load remote catalog: \(error.localizedDescription)"
            }
        }

        // Fallback to a small built-in catalog if remote fails or not provided
        self.catalog = Self.fallbackCatalog()
        TelemetryCenter.emit(
            .system,
            severity: .warning,
            title: "Model catalog fallback used",
            metadata: ["count": "\(self.catalog.count)"]
        )
    }

    private static func fallbackCatalog() -> [ModelCatalogEntry] {
        // Curated working models from Hugging Face - ready to download
        return [
            ModelCatalogEntry(
                name: "Qwen2.5-0.5B (Q4_K_M)",
                backend: .gguf,
                url: "hf://Qwen/Qwen2.5-0.5B-Instruct-GGUF:main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
                sizeBytes: 380_000_000,
                checksumSHA256: nil,
                vendor: "Qwen",
                contextWindow: 32768,
                quantization: "Q4_K_M",
                filename: "qwen2.5-0.5b-instruct-q4_k_m.gguf"
            ),
            ModelCatalogEntry(
                name: "Qwen2.5-1.5B (Q4_K_M)",
                backend: .gguf,
                url: "hf://Qwen/Qwen2.5-1.5B-Instruct-GGUF:main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
                sizeBytes: 970_000_000,
                checksumSHA256: nil,
                vendor: "Qwen",
                contextWindow: 32768,
                quantization: "Q4_K_M",
                filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf"
            ),
            ModelCatalogEntry(
                name: "Qwen2.5-3B (Q4_K_M)",
                backend: .gguf,
                url: "hf://Qwen/Qwen2.5-3B-Instruct-GGUF:main/qwen2.5-3b-instruct-q4_k_m.gguf",
                sizeBytes: 1_900_000_000,
                checksumSHA256: nil,
                vendor: "Qwen",
                contextWindow: 32768,
                quantization: "Q4_K_M",
                filename: "qwen2.5-3b-instruct-q4_k_m.gguf"
            ),
            ModelCatalogEntry(
                name: "Llama-3.2-1B (Q4_K_M)",
                backend: .gguf,
                url:
                    "hf://lmstudio-community/Llama-3.2-1B-Instruct-GGUF:main/Llama-3.2-1B-Instruct-Q4_K_M.gguf",
                sizeBytes: 730_000_000,
                checksumSHA256: nil,
                vendor: "Meta",
                contextWindow: 131072,
                quantization: "Q4_K_M",
                filename: "Llama-3.2-1B-Instruct-Q4_K_M.gguf"
            ),
            ModelCatalogEntry(
                name: "Llama-3.2-3B (Q4_K_M)",
                backend: .gguf,
                url:
                    "hf://lmstudio-community/Llama-3.2-3B-Instruct-GGUF:main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
                sizeBytes: 2_000_000_000,
                checksumSHA256: nil,
                vendor: "Meta",
                contextWindow: 131072,
                quantization: "Q4_K_M",
                filename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf"
            ),
            ModelCatalogEntry(
                name: "Gemma-2-2B (Q4_K_M)",
                backend: .gguf,
                url: "hf://lmstudio-community/gemma-2-2b-it-GGUF:main/gemma-2-2b-it-Q4_K_M.gguf",
                sizeBytes: 1_600_000_000,
                checksumSHA256: nil,
                vendor: "Google",
                contextWindow: 8192,
                quantization: "Q4_K_M",
                filename: "gemma-2-2b-it-Q4_K_M.gguf"
            ),
            ModelCatalogEntry(
                name: "Phi-3.5-Mini (Q4_K_M)",
                backend: .gguf,
                url:
                    "hf://bartowski/Phi-3.5-mini-instruct-GGUF:main/Phi-3.5-mini-instruct-Q4_K_M.gguf",
                sizeBytes: 2_300_000_000,
                checksumSHA256: nil,
                vendor: "Microsoft",
                contextWindow: 131072,
                quantization: "Q4_K_M",
                filename: "Phi-3.5-mini-instruct-Q4_K_M.gguf"
            ),
        ]
    }

    // MARK: - Download

    func download(entry: ModelCatalogEntry) {
        // Build a URLRequest for either direct http(s) or Hugging Face (hf://owner/repo[:rev]/path)
        let request: URLRequest
        if entry.url.lowercased().hasPrefix("hf://"),
            let ref = Self.parseHFURL(entry.url),
            let hfReq = Self.huggingFaceResolveRequest(for: ref, token: Self.huggingFaceToken())
        {
            request = hfReq
        } else if let remoteURL = URL(string: entry.url) {
            request = URLRequest(url: remoteURL)
        } else {
            updateDownload(entry.id, status: .failed(error: "Invalid URL"))
            TelemetryCenter.emit(
                .error, severity: .error, title: "Model download failed",
                metadata: ["reason": "Invalid URL", "name": entry.name])
            return
        }

        // Disk space preflight if size is known
        let (ok, available) = hasSufficientDiskSpace(for: entry.sizeBytes)
        if !ok, let need = entry.sizeBytes {
            let needMB = String(format: "%.2f MB", Double(need) / (1024.0 * 1024.0))
            let haveMB = String(format: "%.2f MB", Double(available) / (1024.0 * 1024.0))
            updateDownload(
                entry.id,
                status: .failed(error: "Not enough free space (need \(needMB), have \(haveMB))"))
            TelemetryCenter.emit(
                .storage,
                severity: .error,
                title: "Insufficient disk space for model",
                metadata: [
                    "name": entry.name,
                    "needBytes": "\(need)",
                    "availableBytes": "\(available)",
                ]
            )
            return
        }

        // Initialize state
        if downloads[entry.id] == nil {
            downloads[entry.id] = DownloadState(entry: entry)
        }
        updateDownload(entry.id) { st in
            st.status = .downloading
            st.progress = 0.0
        }

        TelemetryCenter.emit(
            .system,
            title: "Model download started",
            metadata: [
                "name": entry.name,
                "backend": entry.backend.rawValue,
                "size": "\(entry.sizeBytes ?? 0)",
            ]
        )

        let task = session.downloadTask(with: request)
        taskToEntry[task.taskIdentifier] = entry.id
        task.resume()
    }

    func cancel(entryID: UUID) {
        // Find task by entry id and cancel using async callback
        guard let (taskID, _) = taskToEntry.first(where: { $0.value == entryID }) else {
            updateDownload(entryID, status: .cancelled)
            return
        }
        session.getAllTasks { [weak self] tasks in
            guard let self = self else { return }
            if let task = tasks.first(where: { $0.taskIdentifier == taskID }) {
                task.cancel()
            }
            DispatchQueue.main.async {
                // Remove mapping and update state
                self.taskToEntry = self.taskToEntry.filter { $0.key != taskID }
                self.resumeDataByEntry.removeValue(forKey: entryID)
                self.intentionallyPaused.remove(entryID)
                self.updateDownload(entryID, status: .cancelled)
                TelemetryCenter.emit(
                    .system,
                    title: "Model download cancelled",
                    metadata: ["entryId": entryID.uuidString]
                )
            }
        }
    }

    /// Pause an in-flight download, capturing resume data if available
    func pause(entryID: UUID) {
        guard let (taskID, _) = taskToEntry.first(where: { $0.value == entryID }) else { return }
        session.getAllTasks { [weak self] tasks in
            guard let self = self else { return }
            if let task = tasks.first(where: { $0.taskIdentifier == taskID })
                as? URLSessionDownloadTask
            {
                // Mutate MainActor-isolated state on the main queue to satisfy isolation
                DispatchQueue.main.async {
                    self.intentionallyPaused.insert(entryID)
                }
                task.cancel(byProducingResumeData: { data in
                    DispatchQueue.main.async {
                        if let data { self.resumeDataByEntry[entryID] = data }
                        self.taskToEntry = self.taskToEntry.filter { $0.key != taskID }
                        self.updateDownload(entryID, status: .paused)
                        TelemetryCenter.emit(
                            .system,
                            title: "Model download paused",
                            metadata: ["entryId": entryID.uuidString]
                        )
                    }
                })
            }
        }
    }

    /// Resume a previously paused download using stored resume data
    func resume(entryID: UUID) {
        guard let data = resumeDataByEntry[entryID] else { return }
        let task = session.downloadTask(withResumeData: data)
        taskToEntry[task.taskIdentifier] = entryID
        resumeDataByEntry.removeValue(forKey: entryID)
        intentionallyPaused.remove(entryID)
        updateDownload(entryID) { st in
            st.status = .downloading
        }
        task.resume()
        TelemetryCenter.emit(
            .system,
            title: "Model download resumed",
            metadata: ["entryId": entryID.uuidString]
        )
    }

    // MARK: - Helpers (state + post-processing)

    /// Check if there is sufficient disk space for the expected number of bytes.
    /// Returns (ok, availableBytes)
    private func hasSufficientDiskSpace(for expectedBytes: Int64?) -> (ok: Bool, available: Int64) {
        guard let expected = expectedBytes, expected > 0 else {
            // Unknown size: allow download and rely on OS backpressure
            return (true, 0)
        }
        do {
            let docs = try ModelRegistryLocations.modelsDirectory()
            let values = try docs.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ])
            let available = values.volumeAvailableCapacityForImportantUsage ?? 0
            // Add a safety buffer of 50 MB
            let buffer: Int64 = 50 * 1024 * 1024
            return (available >= expected + buffer, available)
        } catch {
            return (true, 0)
        }
    }

    private func updateDownload(_ id: UUID, status: DownloadStatus) {
        if var st = downloads[id] {
            st.status = status
            downloads[id] = st
        }
    }

    private func updateDownload(_ id: UUID, mutate: (inout DownloadState) -> Void) {
        if var st = downloads[id] {
            mutate(&st)
            downloads[id] = st
        }
    }

    private func finalizeDownload(for entryID: UUID, tempURL: URL, suggestedFilename: String?) {
        guard let entry = downloads[entryID]?.entry else {
            updateDownload(entryID, status: .failed(error: "Missing entry"))
            return
        }

        Task { @MainActor in
            updateDownload(entryID, status: .verifying)

            // Destination in Documents/Models
            do {
                // Ensure Models directory exists
                let modelsDir = try ModelRegistryLocations.modelsDirectory()

                let fileName =
                    entry.filename ?? suggestedFilename ?? URL(string: entry.url)?.lastPathComponent
                    ?? UUID().uuidString
                let destURL = modelsDir.appendingPathComponent(fileName, isDirectory: false)

                // Verify temp file exists and has content before moving
                let fm = FileManager.default
                guard fm.fileExists(atPath: tempURL.path) else {
                    updateDownload(
                        entryID, status: .failed(error: "Download incomplete - temp file missing"))
                    return
                }

                // Check file has reasonable size
                if let attrs = try? fm.attributesOfItem(atPath: tempURL.path),
                    let fileSize = attrs[.size] as? Int64
                {
                    if fileSize < 1024 {
                        updateDownload(
                            entryID,
                            status: .failed(
                                error: "Download incomplete - file too small (\(fileSize) bytes)"))
                        try? fm.removeItem(at: tempURL)
                        return
                    }
                }

                // Replace if exists
                if fm.fileExists(atPath: destURL.path) {
                    try? fm.removeItem(at: destURL)
                }

                // Move from temp to final destination
                try fm.moveItem(at: tempURL, to: destURL)

                // Optional checksum
                if let expected = entry.checksumSHA256, !expected.isEmpty {
                    #if canImport(CryptoKit)
                        let ok = try verifySHA256(fileURL: destURL, expectedHex: expected)
                        if !ok {
                            try? fm.removeItem(at: destURL)
                            updateDownload(
                                entryID, status: .failed(error: "Checksum verification failed"))
                            return
                        }
                    #endif
                }

                // Register
                updateDownload(entryID, status: .registering)
                switch entry.backend {
                case .gguf:
                    ModelRegistry.shared.installGGUF(at: destURL)
                    // Auto-select first GGUF model if none is currently selected
                    await autoSelectFirstGGUFIfNeeded()
                case .coreML:
                    ModelRegistry.shared.installCoreML(at: destURL)
                    // Auto-select first Core ML model if none is currently selected
                    await autoSelectFirstCoreMLIfNeeded()
                case .mlxServer:
                    Log.info("Ignoring legacy MLX server download", category: .llm)
                    if fm.fileExists(atPath: destURL.path) {
                        try? fm.removeItem(at: destURL)
                    }
                    updateDownload(
                        entryID,
                        status: .failed(error: "MLX server installers are no longer supported")
                    )
                    return
                }

                updateDownload(entryID, status: .completed(localURL: destURL))
                TelemetryCenter.emit(
                    .storage,
                    title: "Model installed",
                    metadata: [
                        "name": entry.name,
                        "backend": entry.backend.rawValue,
                        "path": destURL.lastPathComponent,
                    ]
                )
            } catch {
                updateDownload(entryID, status: .failed(error: error.localizedDescription))
                TelemetryCenter.emit(
                    .error,
                    severity: .error,
                    title: "Model download/register failed",
                    metadata: [
                        "name": entry.name,
                        "reason": error.localizedDescription,
                    ]
                )
            }
        }
    }

    #if canImport(CryptoKit)
        private func verifySHA256(fileURL: URL, expectedHex: String) throws -> Bool {
            let data = try Data(contentsOf: fileURL)
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            return hex.lowercased() == expectedHex.lowercased()
        }
    #endif
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloadService: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        let taskID = downloadTask.taskIdentifier
        DispatchQueue.main.async {
            guard let entryID = self.taskToEntry[taskID],
                var st = self.downloads[entryID]
            else { return }

            // Update progress
            if totalBytesExpectedToWrite > 0 {
                st.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                st.totalBytes = totalBytesExpectedToWrite
            } else if let catalogSize = st.entry.sizeBytes, catalogSize > 0 {
                st.progress = min(1.0, Double(totalBytesWritten) / Double(catalogSize))
                st.totalBytes = catalogSize
            } else {
                st.progress = 0.0
            }
            // Update byte counters
            st.bytesWritten = totalBytesWritten

            // Compute instantaneous throughput and smooth with EMA
            let now = Date()
            if let last = st.lastTick {
                let dt = now.timeIntervalSince(last)
                if dt > 0 {
                    let inst = Double(bytesWritten) / dt
                    if let prev = st.averageBytesPerSecond {
                        st.averageBytesPerSecond = 0.6 * inst + 0.4 * prev
                    } else {
                        st.averageBytesPerSecond = inst
                    }
                }
            }
            st.lastTick = now

            st.status = .downloading
            self.downloads[entryID] = st

            // Emit throttled progress telemetry (≈1Hz)
            let lastSent = self.lastProgressEventAt[entryID] ?? .distantPast
            if now.timeIntervalSince(lastSent) >= 1.0 {
                let pct = String(format: "%.0f", (st.progress * 100.0))
                let bps = st.averageBytesPerSecond ?? 0
                TelemetryCenter.emit(
                    .system,
                    title: "Model download progress",
                    metadata: [
                        "entryId": entryID.uuidString,
                        "name": st.entry.name,
                        "progressPct": pct,
                        "bytesWritten": "\(st.bytesWritten)",
                        "totalBytes": "\(st.totalBytes)",
                        "bytesPerSecond": String(format: "%.0f", bps),
                    ]
                )
                self.lastProgressEventAt[entryID] = now
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskID = downloadTask.taskIdentifier
        let filename = downloadTask.response?.suggestedFilename

        // CRITICAL: The temp file at 'location' will be deleted after this method returns.
        // We must copy it to a safe location IMMEDIATELY before dispatching to main.

        // Create a temporary location in our app's tmp directory
        let tmpDir = FileManager.default.temporaryDirectory
        let safeTempURL = tmpDir.appendingPathComponent(UUID().uuidString + ".tmp")

        do {
            // Copy the file to our temporary location before the system deletes it
            try FileManager.default.copyItem(at: location, to: safeTempURL)

            // Now dispatch to main with the safe copy
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    try? FileManager.default.removeItem(at: safeTempURL)  // Clean up if service is gone
                    return
                }
                guard let entryID = self.taskToEntry[taskID] else {
                    try? FileManager.default.removeItem(at: safeTempURL)  // Clean up if no entry
                    return
                }
                self.finalizeDownload(
                    for: entryID, tempURL: safeTempURL, suggestedFilename: filename)
                self.taskToEntry.removeValue(forKey: taskID)
            }
        } catch {
            // If copy fails, report error
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let entryID = self.taskToEntry[taskID] {
                    self.updateDownload(
                        entryID,
                        status: .failed(
                            error: "Failed to preserve download: \(error.localizedDescription)"))
                    self.taskToEntry.removeValue(forKey: taskID)
                }
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let taskID = task.taskIdentifier
        let nsError = error as NSError
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data

        DispatchQueue.main.async {
            if let entryID = self.taskToEntry[taskID] {
                // If we intentionally paused, mark paused; otherwise store resume data (if any) and mark failed
                if self.intentionallyPaused.contains(entryID) {
                    if let data = resumeData { self.resumeDataByEntry[entryID] = data }
                    self.updateDownload(entryID, status: .paused)
                    self.intentionallyPaused.remove(entryID)
                } else if let data = resumeData {
                    self.resumeDataByEntry[entryID] = data
                    self.updateDownload(entryID, status: .failed(error: error.localizedDescription))
                } else {
                    self.updateDownload(entryID, status: .failed(error: error.localizedDescription))
                }
                self.taskToEntry.removeValue(forKey: taskID)
            }
        }
    }

    // MARK: - Auto-Selection Helpers

    /// Auto-select first GGUF model if no GGUF model is currently selected
    @MainActor
    private func autoSelectFirstGGUFIfNeeded() async {
        // Check if a GGUF model is already selected
        let defaults = UserDefaults.standard
        if let existingId = defaults.string(forKey: LlamaCPPiOSLLMService.selectedModelIdKey),
            !existingId.isEmpty,
            let uuid = UUID(uuidString: existingId),
            ModelRegistry.shared.model(id: uuid) != nil
        {
            // Already have a GGUF model selected and it exists
            return
        }

        // No GGUF model selected - pick the first one
        guard let firstGGUF = ModelRegistry.shared.installed.first(where: { $0.backend == .gguf })
        else {
            return
        }

        LlamaCPPiOSLLMService.saveSelection(modelId: firstGGUF.id)
        broadcastAutoSelection(for: firstGGUF)
        Log.info(
            "[ModelDownload] Auto-selected first GGUF model: \(firstGGUF.name)", category: .pipeline
        )
        TelemetryCenter.emit(
            .storage,
            title: "GGUF model auto-selected",
            metadata: ["name": firstGGUF.name, "id": String(firstGGUF.id.uuidString.prefix(8))]
        )
    }

    /// Auto-select first Core ML model if no Core ML model is currently selected
    @MainActor
    private func autoSelectFirstCoreMLIfNeeded() async {
        // Check if a Core ML model is already selected
        let defaults = UserDefaults.standard
        if let existingId = defaults.string(forKey: CoreMLLLMService.selectedModelIdKey),
            !existingId.isEmpty,
            let uuid = UUID(uuidString: existingId),
            ModelRegistry.shared.model(id: uuid) != nil
        {
            // Already have a Core ML model selected and it exists
            return
        }

        // No Core ML model selected - pick the first one
        guard
            let firstCoreML = ModelRegistry.shared.installed.first(where: { $0.backend == .coreML })
        else {
            return
        }

        if let url = firstCoreML.localURL {
            CoreMLLLMService.saveSelection(modelId: firstCoreML.id, modelURL: url)
            broadcastAutoSelection(for: firstCoreML)
            Log.info(
                "[ModelDownload] Auto-selected first Core ML model: \(firstCoreML.name)",
                category: .pipeline)
            TelemetryCenter.emit(
                .storage,
                title: "Core ML model auto-selected",
                metadata: [
                    "name": firstCoreML.name, "id": String(firstCoreML.id.uuidString.prefix(8)),
                ]
            )
        }
    }

    private func broadcastAutoSelection(for model: InstalledModel) {
        NotificationCenter.default.post(
            name: .installedModelAutoSelected,
            object: self,
            userInfo: [
                ModelAutoSelectionPayload.backend: model.backend.rawValue,
                ModelAutoSelectionPayload.modelId: model.id.uuidString,
            ]
        )
    }
}
