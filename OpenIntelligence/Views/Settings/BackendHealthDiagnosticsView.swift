//
//  BackendHealthDiagnosticsView.swift
//  OpenIntelligence
//
//  Diagnostics for active backend health and local server connectivity.
//  Shows availability reasons for Apple FM and provides quick health checks
//  for local OpenAI-compatible servers (MLX, llama.cpp, Ollama presets).
//

import SwiftUI

struct BackendHealthDiagnosticsView: View {
    @ObservedObject var ragService: RAGService

    // MLX config (shared via SettingsView @AppStorage keys)
    #if os(macOS)
    @AppStorage("mlxBaseURL") private var mlxBaseURLString: String = "http://127.0.0.1:17860"
    @AppStorage("mlxModel") private var mlxModel: String = "local-mlx-model"
    @AppStorage("mlxStream") private var mlxStream: Bool = false
    @State private var localHealthMessage: String = "Not checked"
    @State private var localHealthColor: Color = .gray
    @State private var checkingLocal = false
    #endif

    @State private var appleFMStatus: String = "Unknown"
    @State private var appleFMColor: Color = .gray
    #if os(iOS)
    @State private var ggufStatusMessage: String = "No model selected"
    @State private var ggufStatusColor: Color = .gray
    @State private var ggufChecking: Bool = false
    #endif

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DSColors.background, DSColors.surface.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Overview
                    SurfaceCard {
                        SectionHeader(icon: "info.circle", title: "Overview")
                        LabeledContent("Active Backend", value: ragService.llmService.modelName)
                        SectionFooter("Shows the backend currently used by the chat pipeline.")
                    }

                    #if os(macOS)
                    // Local server diagnostics (OpenAI-compatible)
                    localServerCard
                    #endif

                    // Apple Foundation Models diagnostics
                    appleFMCard

                    #if os(iOS)
                    // iOS GGUF local backend diagnostics
                    ggufCard
                    #endif
                }
                .padding(16)
            }
        }
        .navigationTitle("Backend Health")
    }

    // MARK: - Sections

    #if os(macOS)
    @ViewBuilder
    private var localServerCard: some View {
        SurfaceCard {
            SectionHeader(icon: "server.rack", title: "Local OpenAI-Compatible Server")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Base URL")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(mlxBaseURLString)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                HStack {
                    Text("Model")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(mlxModel)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                Toggle("Streaming (SSE)", isOn: $mlxStream)
                    .disabled(true)

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await checkLocalHealth()
                        }
                    } label: {
                        if checkingLocal {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Test Local Server")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Text(localHealthMessage)
                        .font(.caption)
                        .foregroundColor(localHealthColor)

                    Spacer()
                }
                SectionFooter("Use this to verify your local MLX/llama.cpp/Ollama server is reachable.\nExample (MLX): python -m mlx_lm.server --model qwen2.5-7b-instruct --port 17860")
            }
        }
    }
    #endif

    @ViewBuilder
    private var appleFMCard: some View {
        SurfaceCard {
            SectionHeader(icon: "brain.head.profile", title: "Apple Foundation Models")
            HStack(spacing: 8) {
                Text("Status:")
                Text(appleFMStatus)
                    .foregroundColor(appleFMColor)
                Spacer()
                Button("Check") {
                    Task { await checkAppleFMAvailability() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            SectionFooter("Reports availability and any known unavailability reasons when supported by the SDK and hardware.")
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var ggufCard: some View {
        SurfaceCard {
            SectionHeader(icon: "doc.badge.gearshape", title: "GGUF Local (iOS)")
            VStack(alignment: .leading, spacing: 10) {
                // Get selected model from registry
                let modelId = UserDefaults.standard.string(forKey: LlamaCPPiOSLLMService.selectedModelIdKey)
                let registry = ModelRegistry.shared
                let selectedModel = modelId.flatMap { UUID(uuidString: $0) }.flatMap { registry.model(id: $0) }
                
                let modelName = selectedModel?.name ?? "Not selected"
                let modelPath = selectedModel?.localURL?.path ?? "—"
                
                LabeledContent("Selected Model", value: modelName)
                LabeledContent("File", value: modelPath)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Button {
                        Task { await verifyGGUFModel() }
                    } label: {
                        if ggufChecking {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Label("Verify Model File", systemImage: "checkmark.seal")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        Task { await runGGUFSmokeTest() }
                    } label: {
                        Label("Run Smoke Test", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task { await runGGUFBenchmark() }
                    } label: {
                        Label("Benchmark", systemImage: "gauge")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack(spacing: 8) {
                    Circle().fill(ggufStatusColor).frame(width: 8, height: 8)
                    Text(ggufStatusMessage)
                        .font(.caption)
                        .foregroundColor(ggufStatusColor)
                }

                SectionFooter("Verifies the selected .gguf model file and runs a short generation smoke test using the in‑process backend. The current backend uses a stub until the embedded runtime is added.")
            }
        }
    }
    #endif

    #if os(macOS)
    @ViewBuilder
    private var localServerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Base URL")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(mlxBaseURLString)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                HStack {
                    Text("Model")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(mlxModel)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                Toggle("Streaming (SSE)", isOn: $mlxStream)
                    .disabled(true)

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await checkLocalHealth()
                        }
                    } label: {
                        if checkingLocal {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Test Local Server")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Text(localHealthMessage)
                        .font(.caption)
                        .foregroundColor(localHealthColor)

                    Spacer()
                }
            }
        } header: {
            HStack {
                Image(systemName: "server.rack")
                Text("Local OpenAI-Compatible Server")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Use this to verify your local MLX/llama.cpp/Ollama server is reachable.")
                Text("Example (MLX): python -m mlx_lm.server --model qwen2.5-7b-instruct --port 17860")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private var ggufSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                // Get selected model from registry
                let modelId = UserDefaults.standard.string(forKey: LlamaCPPiOSLLMService.selectedModelIdKey)
                let registry = ModelRegistry.shared
                let selectedModel = modelId.flatMap { UUID(uuidString: $0) }.flatMap { registry.model(id: $0) }
                
                let modelName = selectedModel?.name ?? "Not selected"
                let modelPath = selectedModel?.localURL?.path ?? "—"
                
                LabeledContent("Selected Model", value: modelName)
                LabeledContent("File", value: modelPath)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Button {
                        Task { await verifyGGUFModel() }
                    } label: {
                        if ggufChecking {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Label("Verify Model File", systemImage: "checkmark.seal")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        Task { await runGGUFSmokeTest() }
                    } label: {
                        Label("Run Smoke Test", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack(spacing: 8) {
                    Circle().fill(ggufStatusColor).frame(width: 8, height: 8)
                    Text(ggufStatusMessage)
                        .font(.caption)
                        .foregroundColor(ggufStatusColor)
                }
            }
        } header: {
            HStack {
                Image(systemName: "doc.badge.gearshape")
                Text("GGUF Local (iOS)")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Verifies the selected .gguf model file and runs a short generation smoke test using the in‑process backend. The current backend uses a stub until the embedded runtime is added.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    #endif

    @ViewBuilder
    private var appleFMSection: some View {
        Section {
            HStack(spacing: 8) {
                Text("Status:")
                Text(appleFMStatus)
                    .foregroundColor(appleFMColor)
                Spacer()
                Button("Check") {
                    Task { await checkAppleFMAvailability() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } header: {
            HStack {
                Image(systemName: "brain.head.profile")
                Text("Apple Foundation Models")
            }
        } footer: {
            Text("Reports availability and any known unavailability reasons when supported by the SDK and hardware.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    #if os(macOS)
    private func checkLocalHealth() async {
        checkingLocal = true
        localHealthMessage = "Checking..."
        localHealthColor = .blue

        let url = URL(string: mlxBaseURLString) ?? URL(string: "http://127.0.0.1:17860")!
        let svc = LocalOpenAIServerLLMService(
            config: .init(baseURL: url,
                          model: mlxModel.isEmpty ? "local-mlx-model" : mlxModel,
                          chatCompletionsPath: "/v1/chat/completions",
                          stream: mlxStream,
                          headers: nil)
        )
        let ok = await svc.healthCheck()
        checkingLocal = false
        if ok {
            localHealthMessage = "Server reachable"
            localHealthColor = .green
        } else {
            localHealthMessage = "Connection failed"
            localHealthColor = .red
        }
    }
    #endif

    #if os(iOS)
    @MainActor
    private func verifyGGUFModel() async {
        ggufChecking = true
        ggufStatusMessage = "Verifying..."
        ggufStatusColor = .blue

        let defaults = UserDefaults.standard
        if let idString = defaults.string(forKey: LlamaCPPiOSLLMService.selectedModelIdKey),
           let id = UUID(uuidString: idString),
           let model = ModelRegistry.shared.model(id: id),
           let path = model.localURL?.path {
            let exists = FileManager.default.fileExists(atPath: path)
            if exists {
                ggufStatusMessage = "Model file found (\(model.name))"
                ggufStatusColor = .green
            } else {
                ggufStatusMessage = "File not found at saved path"
                ggufStatusColor = .red
            }
        } else {
            ggufStatusMessage = "No model selected"
            ggufStatusColor = .orange
        }

        ggufChecking = false
    }

    @MainActor
    private func runGGUFSmokeTest() async {
        ggufChecking = true
        ggufStatusMessage = "Running smoke test..."
        ggufStatusColor = .blue

        guard let svc = LlamaCPPiOSLLMService.fromRegistry() else {
            ggufStatusMessage = "No GGUF model configured"
            ggufStatusColor = .orange
            ggufChecking = false
            return
        }

        do {
            let cfg = InferenceConfig(maxTokens: 8, temperature: 0.0)
            let response = try await svc.generate(prompt: "Hello", context: nil, config: cfg)
            if response.text.isEmpty {
                ggufStatusMessage = "Smoke test returned empty response"
                ggufStatusColor = .red
            } else {
                ggufStatusMessage = "Smoke test OK (\(response.tokensGenerated) tokens)"
                ggufStatusColor = .green
            }
        } catch {
            ggufStatusMessage = "Smoke test failed: \(error.localizedDescription)"
            ggufStatusColor = .red
        }

        ggufChecking = false
    }

    @MainActor
    private func runGGUFBenchmark() async {
        ggufChecking = true
        ggufStatusMessage = "Benchmarking..."
        ggufStatusColor = .blue

        guard let svc = LlamaCPPiOSLLMService.fromRegistry() else {
            ggufStatusMessage = "No GGUF model configured"
            ggufStatusColor = .orange
            ggufChecking = false
            return
        }

        do {
            let config = InferenceConfig(maxTokens: 64, temperature: 0.2)
            let start = Date()
            let response = try await svc.generate(prompt: "Count from one to ten with short phrases.", context: nil, config: config)
            let total = Date().timeIntervalSince(start)
            let ttft = response.timeToFirstToken ?? 0
            let tps = response.tokensPerSecond ?? Float(response.tokensGenerated) / Float(max(total, 0.0001))
            ggufStatusMessage = String(format: "Benchmark OK • TTFT %.2fs • %.1f tok/s • %d tokens", ttft, tps, response.tokensGenerated)
            ggufStatusColor = .green
        } catch {
            ggufStatusMessage = "Benchmark failed: \(error.localizedDescription)"
            ggufStatusColor = .red
        }

        ggufChecking = false
    }
    #endif

    @MainActor
    private func checkAppleFMAvailability() async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // Create a temporary service to read availability safely on main thread.
            let fm = AppleFoundationLLMService()
            if fm.isAvailable {
                appleFMStatus = "Available"
                appleFMColor = .green
            } else if let reason = fm.unavailabilityReason {
                appleFMStatus = reason
                appleFMColor = .orange
            } else {
                appleFMStatus = "Unavailable (unknown reason)"
                appleFMColor = .red
            }
            return
        }
        appleFMStatus = "Requires iOS 26 SDK"
        appleFMColor = .gray
        #else
        appleFMStatus = "FoundationModels SDK not available in this build"
        appleFMColor = .gray
        #endif
    }
}

#Preview {
    NavigationView {
        BackendHealthDiagnosticsView(ragService: RAGService())
    }
    #if os(iOS)
    .navigationViewStyle(.stack)
    #endif
}
