//
//  InstalledModel.swift
//  OpenIntelligence
//
//  Cartridge-style local model descriptor and lightweight registry interfaces.
//  Phase 1: GGUF focus on iOS, extensible to CoreML and MLX.
//

import Foundation

// MARK: - Backends supported by the cartridge system

enum ModelBackend: String, Codable, CaseIterable, Identifiable {
    case gguf       // iOS: in-process llama.cpp runtime (when available), file: .gguf
    case coreML     // iOS/macOS: Core ML LLM (.mlpackage)
    case mlxServer  // macOS: MLX local server descriptor (no file payload)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gguf: return "GGUF"
        case .coreML: return "Core ML"
        case .mlxServer: return "MLX (Server)"
        }
    }

    var iconName: String {
        switch self {
        case .gguf: return "doc.badge.gearshape"
        case .coreML: return "cpu"
        case .mlxServer: return "server.rack"
        }
    }
}

// MARK: - Installed model “cartridge”

struct InstalledModel: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var backend: ModelBackend
    var localURL: URL?            // File URL for gguf/coreML; nil for mlx server descriptor
    var sizeBytes: Int64?
    var contextWindow: Int?       // Tokens (if known)
    var tokenizerType: String?    // e.g., "llama", "sentencepiece", "bpe"
    var quantization: String?     // e.g., "Q4_K_M", "Q8_0", or CoreML quant detail
    var supportsToolUse: Bool     // adapter can flip this on load if detected
    var installedAt: Date
    var version: String?          // optional semantic version or commit tag
    var vendor: String?           // e.g., "Gemma", "Qwen", "Llama"
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        backend: ModelBackend,
        localURL: URL?,
        sizeBytes: Int64? = nil,
        contextWindow: Int? = nil,
        tokenizerType: String? = nil,
        quantization: String? = nil,
        supportsToolUse: Bool = false,
        installedAt: Date = Date(),
        version: String? = nil,
        vendor: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.localURL = localURL
        self.sizeBytes = sizeBytes
        self.contextWindow = contextWindow
        self.tokenizerType = tokenizerType
        self.quantization = quantization
        self.supportsToolUse = supportsToolUse
        self.installedAt = installedAt
        self.version = version
        self.vendor = vendor
        self.notes = notes
    }
}

// MARK: - Registry persistence (file locations)

enum ModelRegistryLocations {
    private static var didMigrateFromAppSupport = false

    static func modelsDirectory() throws -> URL {
        let fm = FileManager.default
        // Use Documents directory - persists across app reinstalls and rebuilds
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("Models", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Migrate from old Application Support location if needed
        if !didMigrateFromAppSupport {
            didMigrateFromAppSupport = true
            if let legacyAppSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent("Models", isDirectory: true),
               fm.fileExists(atPath: legacyAppSupport.path) {
                do {
                    let contents = try fm.contentsOfDirectory(at: legacyAppSupport, includingPropertiesForKeys: nil)
                    for item in contents {
                        let destination = dir.appendingPathComponent(item.lastPathComponent, isDirectory: item.hasDirectoryPath)
                        if fm.fileExists(atPath: destination.path) { continue }
                        try fm.moveItem(at: item, to: destination)
                    }
                    try? fm.removeItem(at: legacyAppSupport)
                    Log.info("Migrated models from Application Support to Documents", category: .pipeline)
                } catch {
                    Log.warning("Failed to migrate models from Application Support: \(error.localizedDescription)", category: .pipeline)
                }
            }
        }

        // Documents directory is automatically backed up by iCloud/iTunes, but models are large
        // Mark as excluded from backup to save user's iCloud storage
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        do {
            var mutableDir = dir
            try mutableDir.setResourceValues(resourceValues)
        } catch {
            Log.warning("Unable to mark models directory as do-not-backup: \(error.localizedDescription)", category: .pipeline)
        }

        return dir
    }

    static func registryFileURL() throws -> URL {
        try modelsDirectory().appendingPathComponent("installed_models.json")
    }
}

// MARK: - Minimal tokenizer estimation descriptor (stub)

/// Lightweight descriptor to allow future token length estimation.
/// Adapters can vend an estimator keyed by backend + model id.
struct TokenizerEstimatorDescriptor: Codable, Equatable {
    enum Kind: String, Codable {
        case llama
        case sentencePiece
        case bpe
        case unknown
    }
    var kind: Kind
    var modelHint: String?   // optional filename/tokenizer path for precise init (future)
}

// MARK: - Notifications

extension Notification.Name {
    /// Emitted when the downloader auto-selects a newly installed cartridge.
    static let installedModelAutoSelected = Notification.Name("InstalledModelAutoSelected")
}

enum ModelAutoSelectionPayload {
    static let backend = "backend"
    static let modelId = "modelId"
}

// MARK: - Cartridge selection state

/// Active selection for generation: either a built-in type (Apple/OpenAI/etc.)
/// or a cartridge from the registry (by id).
enum ActiveModelSelection: Codable, Equatable {
    case builtin(type: String)         // maps to LLMModelType.rawValue
    case cartridge(id: UUID)

    private enum CodingKeys: String, CodingKey {
        case tag, type, id
    }

    private enum Tag: String, Codable {
        case builtin, cartridge
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(Tag.self, forKey: .tag)
        switch tag {
        case .builtin:
            let type = try c.decode(String.self, forKey: .type)
            self = .builtin(type: type)
        case .cartridge:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .cartridge(id: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .builtin(let type):
            try c.encode(Tag.builtin, forKey: .tag)
            try c.encode(type, forKey: .type)
        case .cartridge(let id):
            try c.encode(Tag.cartridge, forKey: .tag)
            try c.encode(id, forKey: .id)
        }
    }
}
