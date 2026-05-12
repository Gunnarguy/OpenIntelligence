//
//  EventToasts.swift
//  OpenIntelligence
//
//  Lightweight ephemeral ribbon toasts for stage milestones.
//  Appears from the top with haptics, auto-dismisses, supports stacking.
//  Created by Cline on 10/29/25.
//

import Combine
import SwiftUI

// MARK: - Toast Item Model

struct ToastItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let icon: String
    let tint: Color
    let haptic: Bool
    let timestamp: Date
    
    init(id: UUID = UUID(), title: String, icon: String, tint: Color, haptic: Bool = true) {
        self.id = id
        self.title = title
        self.icon = icon
        self.tint = tint
        self.haptic = haptic
        self.timestamp = Date()
    }
    
    /// Factory methods for common stage toasts
    static func embedding() -> ToastItem {
        ToastItem(title: "Embedding query", icon: "brain.head.profile", tint: DSColors.accent)
    }
    
    static func searching(topK: Int) -> ToastItem {
        ToastItem(title: "Searching top \(topK)", icon: "magnifyingglass", tint: .green)
    }
    
    static func generating(modelName: String? = nil) -> ToastItem {
        let title = modelName.map { "Generating via \($0)" } ?? "Generating…"
        return ToastItem(title: title, icon: "sparkles", tint: DSColors.accent)
    }
    
    static func complete(tokenCount: Int? = nil) -> ToastItem {
        let title = tokenCount.map { "Done • \($0) tokens" } ?? "Complete"
        return ToastItem(title: title, icon: "checkmark.circle.fill", tint: .green, haptic: false)
    }
    
    static func error(_ message: String) -> ToastItem {
        ToastItem(title: message, icon: "exclamationmark.triangle.fill", tint: .red)
    }
}

// MARK: - Single Toast View

struct EventToastView: View {
    let toast: ToastItem
    
    @State private var isVisible: Bool = false
    
    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            // Animated icon
            Image(systemName: toast.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(toast.tint)
                .symbolEffect(.bounce, options: .nonRepeating, value: isVisible)
            
            Text(toast.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DSColors.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 8)
        .background(
            .ultraThinMaterial,
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(toast.tint.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .scaleEffect(isVisible ? 1.0 : 0.9)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            if toast.haptic {
                DSHaptics.light()
            }
            withAnimation(DSAnimations.snappySpring) {
                isVisible = true
            }
        }
    }
}

// MARK: - Toast Stack Container

struct ToastStackView: View {
    let items: [ToastItem]
    let maxVisible: Int
    
    init(items: [ToastItem], maxVisible: Int = 3) {
        self.items = items
        self.maxVisible = maxVisible
    }
    
    /// Show only the most recent toasts
    private var visibleItems: [ToastItem] {
        Array(items.suffix(maxVisible))
    }
    
    var body: some View {
        VStack(spacing: 6) {
            ForEach(visibleItems) { toast in
                EventToastView(toast: toast)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        )
                    )
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .animation(DSAnimations.snappySpring, value: items.map(\.id))
    }
}

// MARK: - Toast Manager (Observable)

@MainActor
final class ToastManager: ObservableObject {
    @Published private(set) var toasts: [ToastItem] = []
    
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    
    /// Show a toast with auto-dismiss after duration
    func show(_ toast: ToastItem, duration: TimeInterval = 2.5) {
        // Cancel any existing dismiss task for this ID
        dismissTasks[toast.id]?.cancel()
        
        // Add toast
        toasts.append(toast)
        
        // Schedule dismiss
        let taskId = toast.id
        dismissTasks[taskId] = Task {
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled {
                dismiss(id: taskId)
            }
        }
    }
    
    /// Dismiss a specific toast
    func dismiss(id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)
        toasts.removeAll { $0.id == id }
    }
    
    /// Clear all toasts
    func clearAll() {
        for task in dismissTasks.values {
            task.cancel()
        }
        dismissTasks.removeAll()
        toasts.removeAll()
    }
}

// MARK: - View Modifier for Easy Toast Integration

struct ToastOverlayModifier: ViewModifier {
    @ObservedObject var manager: ToastManager
    
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            ToastStackView(items: manager.toasts)
        }
    }
}

extension View {
    func toastOverlay(_ manager: ToastManager) -> some View {
        modifier(ToastOverlayModifier(manager: manager))
    }
}

// MARK: - Preview

#Preview("Event Toasts") {
    struct PreviewWrapper: View {
        @StateObject private var manager = ToastManager()
        
        var body: some View {
            ZStack {
                DSColors.background.ignoresSafeArea()
                
                VStack(spacing: DSSpacing.lg) {
                    Spacer()
                    
                    Button("Show Embedding") {
                        manager.show(.embedding())
                    }
                    
                    Button("Show Searching") {
                        manager.show(.searching(topK: 3))
                    }
                    
                    Button("Show Generating") {
                        manager.show(.generating(modelName: "Apple Intelligence"))
                    }
                    
                    Button("Show Complete") {
                        manager.show(.complete(tokenCount: 256))
                    }
                    
                    Button("Show Error") {
                        manager.show(.error("Rate limit exceeded"))
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .toastOverlay(manager)
        }
    }
    
    return PreviewWrapper()
}
