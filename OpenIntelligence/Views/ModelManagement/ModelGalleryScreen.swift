//
//  ModelGalleryScreen.swift
//  OpenIntelligence
//
//  Clean model download gallery
//

import SwiftUI

struct ModelGalleryScreen: View {
    @ObservedObject var ragService: RAGService
    @StateObject private var downloadService = ModelDownloadService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Currently Downloading
                if !activeDownloads.isEmpty {
                    Section("Downloading") {
                        ForEach(activeDownloads, id: \.id) { state in
                            DownloadRowClean(state: state, downloadService: downloadService)
                        }
                    }
                }

                // Available Models
                Section("Available Models") {
                    ForEach(downloadService.catalog) { entry in
                        ModelCatalogRowClean(entry: entry, downloadService: downloadService)
                    }
                }
            }
            .navigationTitle("Model Gallery")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                if downloadService.catalog.isEmpty {
                    await downloadService.loadCatalog(from: nil)
                }
            }
        }
    }

    private var activeDownloads: [DownloadState] {
        downloadService.downloads.values
            .filter { state in
                switch state.status {
                case .downloading, .verifying, .registering:
                    return true
                default:
                    return false
                }
            }
            .sorted { $0.progress > $1.progress }
    }
}

// MARK: - Model Catalog Row

struct ModelCatalogRowClean: View {
    let entry: ModelCatalogEntry
    @ObservedObject var downloadService: ModelDownloadService

    private var downloadState: DownloadState? {
        downloadService.downloads[entry.id]
    }

    private var isDownloading: Bool {
        guard let state = downloadState else { return false }
        switch state.status {
        case .downloading, .verifying, .registering:
            return true
        default:
            return false
        }
    }

    private var isCompleted: Bool {
        guard let state = downloadState else { return false }
        if case .completed = state.status {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "cube.fill")
                    .font(.title2)
                    .foregroundStyle(.blue.gradient)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.body.weight(.medium))

                    HStack(spacing: 6) {
                        if let vendor = entry.vendor {
                            Text(vendor)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("•")
                                .foregroundColor(.secondary)
                        }

                        if let size = entry.sizeBytes {
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let quant = entry.quantization {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(quant)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green.gradient)
                        .font(.title3)
                } else if isDownloading {
                    ProgressView()
                } else {
                    Button {
                        downloadService.download(entry: entry)
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue.gradient)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let context = entry.contextWindow {
                Text("\(context.formatted())K context")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Download Row

struct DownloadRowClean: View {
    let state: DownloadState
    @ObservedObject var downloadService: ModelDownloadService

    private var statusText: String {
        switch state.status {
        case .downloading:
            let pct = Int(state.progress * 100)
            return "\(pct)%"
        case .verifying:
            return "Verifying..."
        case .registering:
            return "Installing..."
        case .completed:
            return "Complete"
        case .failed(let error):
            return "Failed: \(error)"
        case .paused:
            return "Paused"
        case .cancelled:
            return "Cancelled"
        case .idle:
            return "Waiting..."
        }
    }

    private var speedText: String? {
        guard case .downloading = state.status,
            let bps = state.averageBytesPerSecond,
            bps > 0
        else { return nil }
        let mbps = bps / (1024 * 1024)
        return String(format: "%.1f MB/s", mbps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.entry.name)
                        .font(.body.weight(.medium))

                    HStack(spacing: 6) {
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let speed = speedText {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(speed)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Button {
                    if case .downloading = state.status {
                        downloadService.pause(entryID: state.id)
                    } else if case .paused = state.status {
                        downloadService.resume(entryID: state.id)
                    } else {
                        downloadService.cancel(entryID: state.id)
                    }
                } label: {
                    Image(systemName: pauseOrCancelIcon)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Progress bar
            if case .downloading = state.status {
                ProgressView(value: state.progress)
                    .tint(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private var pauseOrCancelIcon: String {
        switch state.status {
        case .downloading:
            return "pause.circle.fill"
        case .paused:
            return "play.circle.fill"
        default:
            return "xmark.circle.fill"
        }
    }
}
