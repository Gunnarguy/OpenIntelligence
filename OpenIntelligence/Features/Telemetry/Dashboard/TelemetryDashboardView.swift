import SwiftUI

struct TelemetryDashboardView: View {
    @ObservedObject private var telemetry = TelemetryCenter.shared
    @State private var selectedFilter: TelemetrySeverity? = nil

    private var filteredEvents: [TelemetryEvent] {
        if let filter = selectedFilter {
            return telemetry.events.filter { $0.severity == filter }.reversed()
        }
        return telemetry.events.reversed()
    }

    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                colors: [
                    DSColors.background,
                    DSColors.surface.opacity(0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                modernFilterBar

                if filteredEvents.isEmpty {
                    EmptyTelemetryView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: DSSpacing.md) {
                            ForEach(filteredEvents) { event in
                                ModernTelemetryCard(event: event)
                            }
                        }
                        .padding(DSSpacing.lg)
                    }
                }
            }
        }
        .navigationTitle("Telemetry Console")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    telemetry.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(telemetry.events.isEmpty)
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button {
                    telemetry.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(telemetry.events.isEmpty)
            }
            #endif
        }
    }

    private var modernFilterBar: some View {
        VStack(spacing: DSSpacing.md) {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.accentColor)
                Text("Filter")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            Picker("Severity", selection: $selectedFilter) {
                Text("All").tag(TelemetrySeverity?.none)
                ForEach(TelemetrySeverity.allCases, id: \.self) { severity in
                    Text(severity.rawValue.capitalized).tag(TelemetrySeverity?.some(severity))
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(DSSpacing.lg)
        .background(DSColors.background)
    }
}

// MARK: - Modern Components

private struct EmptyTelemetryView: View {
    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.1),
                                Color.accentColor.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "waveform.path.ecg")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: DSSpacing.sm) {
                Text("No Telemetry Yet")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Run an import or chat to see live metrics")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ModernTelemetryCard: View {
    let event: TelemetryEvent

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(alignment: .top) {
                // Category icon
                ZStack {
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .fill(categoryColor.opacity(0.2))
                        .frame(width: DSSpacing.tapTarget, height: DSSpacing.tapTarget)

                    Image(systemName: event.category.symbolName)
                        .foregroundStyle(categoryColor)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(event.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let duration = event.formattedDuration {
                        HStack(spacing: DSSpacing.xs) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(duration)
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                    // Severity badge
                    Text(event.severity.rawValue.capitalized)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
                        .background(severityColor.opacity(0.2))
                        .foregroundStyle(DSColors.readable(severityColor))
                        .clipShape(Capsule())

                    Text(event.formattedTimestamp)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Metadata
            if !event.metadata.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    ForEach(event.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(alignment: .top) {
                            Text("\(key):")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 80, alignment: .leading)
                            Text(value)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.top, DSSpacing.xs)
            }
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    private var severityColor: Color {
        switch event.severity {
        case .info: return DSColors.accent
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var categoryColor: Color {
        switch event.category {
        case .ingestion: return DSColors.accent
        case .embedding: return DSColors.accent
        case .retrieval: return .green
        case .generation: return .orange
        case .storage: return .secondary
        case .system: return .secondary
        case .billing: return .secondary
        case .error: return .red
        }
    }
}

// Legacy TelemetryRow kept for compatibility
private struct TelemetryRow: View {
    let event: TelemetryEvent
    var body: some View {
        ModernTelemetryCard(event: event)
    }
}

#Preview {
    TelemetryDashboardView()
}
