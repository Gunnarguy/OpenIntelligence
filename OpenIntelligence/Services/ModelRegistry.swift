//
//  ModelRegistry.swift
//  OpenIntelligence
//
//  Minimal cartridge-style registry for locally installed models.
//  Phase 1: Persist GGUF/Core ML/MLX descriptors, expose add/remove/find APIs,
//  and hook GGUF import path so selections become first-class cartridges.
//

import Combine
import Foundation

@MainActor
final class ModelRegistry: ObservableObject {
    static let shared = ModelRegistry()

    @Published private(set) var installed: [InstalledModel] = []
    @Published private(set) var isLoaded: Bool = false

    private let saveQueue = DispatchQueue(label: "ai.openintelligence.modelregistry.save", qos: .utility)

    private init() {
        Task {
            await load()
            isLoaded = true
        }
    }

    // MARK: - Persistence

    func load() async {
        do {
            let url = try ModelRegistryLocations.registryFileURL()
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let models = try JSONDecoder().decode([InstalledModel].self, from: data)
                installed = models
                Log.info(
                    "[ModelRegistry] Loaded \(models.count) models from registry",
                    category: .pipeline)
            } else {
                installed = []
                Log.info(
                    "[ModelRegistry] No registry file found, starting with empty registry",
                    category: .pipeline)
            }
        } catch {
            Log.warning(
                "[ModelRegistry] Failed to load registry: \(error.localizedDescription)",
                category: .pipeline)
            installed = []
        }
    }

    private func saveSnapshot(_ models: [InstalledModel]) {
        do {
            let url = try ModelRegistryLocations.registryFileURL()
            let data = try JSONEncoder().encode(models)
            // Write atomically to avoid partial writes
            try data.write(to: url, options: .atomic)
        } catch {
            Log.warning(
                "[ModelRegistry] Failed to save registry: \(error.localizedDescription)",
                category: .pipeline)
        }
    }

    private func scheduleSave() {
        let snapshot = installed
        saveQueue.async { [snapshot] in
            do {
                let url = try ModelRegistryLocations.registryFileURL()
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                Log.warning(
                    "[ModelRegistry] Failed to save registry (bg): \(error.localizedDescription)",
                    category: .pipeline)
            }
        }
    }

    private func deleteFileAsync(at url: URL, retryCount: Int = 2) {
        let path = url.path
        saveQueue.async { [weak self] in
            guard let self else { return }
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: path) else { return }
            guard fileManager.isDeletableFile(atPath: path) else {
                Task { @MainActor [weak self] in
                    self?.logDeletionFailure(url: url, reason: "File not deletable at path")
                }
                return
            }
            do {
                try fileManager.removeItem(atPath: path)
                Log.info(
                    "[ModelRegistry] Deleted model file: \(url.lastPathComponent)",
                    category: .pipeline)
            } catch {
                if retryCount > 0,
                   let nsError = error as NSError?,
                   nsError.domain == NSPOSIXErrorDomain,
                   nsError.code == Int(POSIXError.Code.EBUSY.rawValue) {
                    let delay = DispatchTimeInterval.milliseconds(400)
                    self.saveQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self else { return }
                        Task { @MainActor [weak self] in
                            self?.deleteFileAsync(at: url, retryCount: retryCount - 1)
                        }
                    }
                } else {
                    Task { @MainActor [weak self] in
                        self?.logDeletionFailure(
                            url: url,
                            reason: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func logDeletionFailure(url: URL, reason: String) {
        Log.warning(
            "[ModelRegistry] Failed to delete model file: \(reason)",
            category: .pipeline)
    }

    // MARK: - CRUD

    func all() -> [InstalledModel] { installed }

    func model(id: UUID) -> InstalledModel? {
        installed.first(where: { $0.id == id })
    }

    func remove(id: UUID) {
        guard let model = installed.first(where: { $0.id == id }) else { return }
        remove(model, deleteFromDisk: false)
    }

    func remove(_ model: InstalledModel, deleteFromDisk: Bool) {
        installed.removeAll { $0.id == model.id }
        scheduleSave()
        if deleteFromDisk, let url = model.localURL {
            deleteFileAsync(at: url)
        }
        TelemetryCenter.emit(
            .storage,
            title: "Model removed",
            metadata: [
                "id": String(model.id.uuidString.prefix(8)),
                "name": model.name,
                "backend": model.backend.rawValue,
            ]
        )
    }

    /// Install a GGUF file (copied into Documents/Models externally).
    func installGGUF(at localURL: URL) {
        // Dedup by path
        if let existingIdx = installed.firstIndex(where: {
            $0.localURL?.path == localURL.path && $0.backend == .gguf
        }) {
            // Refresh metadata (size, notes) if needed
            var current = installed[existingIdx]
            current.sizeBytes = fileSize(at: localURL)
            current.name = localURL.lastPathComponent
            current.vendor = inferVendor(from: localURL.lastPathComponent)
            installed[existingIdx] = current
            scheduleSave()
            Log.info(
                "[ModelRegistry] Updated existing GGUF entry: \(current.name)", category: .pipeline)
            return
        }

        let model = InstalledModel(
            name: localURL.lastPathComponent,
            backend: .gguf,
            localURL: localURL,
            sizeBytes: fileSize(at: localURL),
            contextWindow: nil,  // unknown until runtime/metadata parsed
            tokenizerType: "llama",
            quantization: inferQuant(from: localURL.lastPathComponent),
            supportsToolUse: false,
            installedAt: Date(),
            version: nil,
            vendor: inferVendor(from: localURL.lastPathComponent),
            notes: nil
        )
        installed.append(model)
        scheduleSave()
        Log.info("[ModelRegistry] Installed GGUF: \(model.name)", category: .pipeline)
        TelemetryCenter.emit(
            .storage,
            title: "GGUF model registered",
            metadata: [
                "name": model.name,
                "size": "\(model.sizeBytes ?? 0)",
            ]
        )
    }

    /// Install a Core ML LLM package (.mlpackage)
    func installCoreML(at localURL: URL) {
        // Dedup by path
        if let existingIdx = installed.firstIndex(where: {
            $0.localURL?.path == localURL.path && $0.backend == .coreML
        }) {
            var current = installed[existingIdx]
            current.sizeBytes = fileSize(at: localURL)
            current.name = localURL.lastPathComponent
            installed[existingIdx] = current
            scheduleSave()
            Log.info(
                "[ModelRegistry] Updated existing CoreML entry: \(current.name)",
                category: .pipeline)
            return
        }

        let model = InstalledModel(
            name: localURL.lastPathComponent,
            backend: .coreML,
            localURL: localURL,
            sizeBytes: fileSize(at: localURL),
            contextWindow: nil,
            tokenizerType: nil,
            quantization: nil,
            supportsToolUse: false,
            installedAt: Date(),
            version: nil,
            vendor: nil,
            notes: nil
        )
        installed.append(model)
        scheduleSave()
        Log.info("[ModelRegistry] Installed CoreML: \(model.name)", category: .pipeline)
        TelemetryCenter.emit(
            .storage,
            title: "Core ML model registered",
            metadata: [
                "name": model.name,
                "size": "\(model.sizeBytes ?? 0)",
            ]
        )
    }

    // MARK: - Helpers

    private func fileSize(at url: URL) -> Int64? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs[.size] as? NSNumber)?.int64Value
        } catch {
            return nil
        }
    }

    private func inferVendor(from filename: String) -> String? {
        let lower = filename.lowercased()
        if lower.contains("gemma") { return "Gemma" }
        if lower.contains("qwen") { return "Qwen" }
        if lower.contains("llama") { return "Llama" }
        if lower.contains("mistral") { return "Mistral" }
        if lower.contains("phi") { return "Phi" }
        return nil
    }

    private func inferQuant(from filename: String) -> String? {
        // Heuristic for GGUF quant tags
        let upper = filename.uppercased()
        let known = ["Q2_K", "Q3_K", "Q4_K", "Q5_K", "Q6_K", "Q8_0", "Q4_0", "Q5_0", "Q3_0"]
        for tag in known {
            if upper.contains(tag) { return tag }
        }
        return nil
    }
}

// MARK: - Model Activation Coordinator

@MainActor
enum ModelActivationService {
    static func activate(
        _ installed: InstalledModel, ragService: RAGService, settings: SettingsStore
    ) async {
        switch installed.backend {
        case .gguf:
            // Persist selection even if runtime is not yet bundled so the user can set Primary now.
            let hasRuntime = LlamaCPPiOSLLMService.runtimeAvailable
            guard let url = installed.localURL, FileManager.default.fileExists(atPath: url.path)
            else {
                Log.warning("GGUF file missing on disk", category: .llm)
                return
            }
            // Save selection and switch Settings to GGUF Local
            LlamaCPPiOSLLMService.saveSelection(modelId: installed.id)
            settings.selectedModel = .ggufLocal
            AutoTuneService.tuneForSelection(selectedModel: .ggufLocal)

            // Activate immediately if runtime is linked; otherwise defer until runtime is added.
            if hasRuntime, let service = LlamaCPPiOSLLMService.fromRegistry() {
                await ragService.updateLLMService(service)
                Log.info("Activated GGUF model immediately", category: .llm)
            } else {
                Log.warning(
                    "GGUF runtime not bundled; selection persisted and will activate once runtime is linked",
                    category: .llm)
            }
        case .coreML:
            guard let url = installed.localURL, FileManager.default.fileExists(atPath: url.path)
            else {
                Log.warning("Core ML package missing on disk", category: .llm)
                return
            }
            CoreMLLLMService.saveSelection(modelId: installed.id, modelURL: url)
            settings.selectedModel = .coreMLLocal
            AutoTuneService.tuneForSelection(selectedModel: .coreMLLocal)
            if let service = await CoreMLLLMService.fromRegistry() {
                await ragService.updateLLMService(service)
            }
        case .mlxServer:
            Log.info("Ignoring legacy MLX server entry", category: .llm)
        }
    }
}
