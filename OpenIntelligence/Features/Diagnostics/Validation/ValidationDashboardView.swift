#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

struct ValidationDashboardView: View {
    @StateObject private var viewModel: ValidationDashboardViewModel
    
    @State private var query = "What is the towing capacity?"
    @State private var isDeepThink = false
    
    @State private var showManifestImporter = false
    @State private var showDocumentImporter = false
    
    init(ragService: RAGService, settingsStore: SettingsStore) {
        _viewModel = StateObject(wrappedValue: ValidationDashboardViewModel(ragService: ragService, settingsStore: settingsStore))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RAG Validation & Benchmarks")
                .font(.largeTitle)
                .bold()
                .padding(.bottom, 8)
            
            Text("Execute pre-configured RAG validation suites visually, monitoring document ingestion, chunking, and reasoning outputs in real-time.")
                .foregroundColor(.secondary)
            
            HStack {
                Button(action: { showManifestImporter = true }) {
                    Label("Load JSON Suite", systemImage: "doc.badge.gearshape")
                }
                .disabled(viewModel.isRunning)
                
                Button(action: { showDocumentImporter = true }) {
                    Label("Load Document", systemImage: "doc.text")
                }
                .disabled(viewModel.isRunning)
                
                if let url = viewModel.selectedFileURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            HStack {
                TextField("Query (for single document)", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isRunning || viewModel.selectedFileURL?.pathExtension == "json")
                
                Toggle("Deep Think", isOn: $isDeepThink)
                    .disabled(viewModel.isRunning || viewModel.selectedFileURL?.pathExtension == "json")
                
                Button(action: runSingleDocument) {
                    Text(viewModel.isRunning ? "Running..." : "Run Test")
                        .bold()
                }
                .disabled(viewModel.isRunning || query.isEmpty || viewModel.selectedFileURL == nil || viewModel.selectedFileURL?.pathExtension == "json")
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            Text("Execution Console")
                .font(.headline)
            
            ScrollView {
                Text(viewModel.outputText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            #if os(macOS)
            .background(Color(NSColor.textBackgroundColor))
            #else
            .background(Color(UIColor.secondarySystemBackground))
            #endif
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
        #endif
        .fileImporter(isPresented: $showManifestImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            handleFileImport(result: result, isManifest: true)
        }
        .fileImporter(isPresented: $showDocumentImporter, allowedContentTypes: [.pdf, .plainText], allowsMultipleSelection: false) { result in
            handleFileImport(result: result, isManifest: false)
        }
        .onAppear {
            autoStartIfVisualMode()
        }
    }
    
    private func autoStartIfVisualMode() {
        guard DebugRAGValidationHarness.isVisualModeEnabled,
              DebugRAGValidationHarness.lastReport == nil,
              let config = DebugRAGValidationHarness.cachedConfiguration else { return }
        
        // Populate UI state so they see what's happening
        if !config.inputURLs.isEmpty {
            viewModel.selectedFileURL = config.inputURLs.first
        }
        query = config.query
        isDeepThink = config.qualityMode == .deepThink || config.qualityMode == .maximum
        
        // Give the UI a tiny moment to render the sheet, then auto-run
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let url = config.inputURLs.first, url.pathExtension == "json" {
                viewModel.loadAndRunSuite(from: url)
            } else {
                runSingleDocument()
            }
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>, isManifest: Bool) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if isManifest {
                viewModel.loadAndRunSuite(from: url)
            } else {
                viewModel.selectedFileURL = url
            }
        case .failure(let error):
            viewModel.outputText = "Error selecting file: \(error.localizedDescription)"
        }
    }
    
    private func runSingleDocument() {
        guard let url = viewModel.selectedFileURL else { return }
        let mode: RAGQualityMode = isDeepThink ? .deepThink : .standard
        viewModel.runSingleDocument(url: url, query: query, qualityMode: mode)
    }
}
#endif
