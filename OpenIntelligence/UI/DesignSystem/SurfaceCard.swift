import SwiftUI

/// Reusable card container matching the app's modern surface style.
/// - Uses DSColors.surface background, rounded corners, subtle shadow.
/// - Wrap settings and diagnostics content for visual parity across the app.
public struct SurfaceCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let shadowOpacity: CGFloat
    private let shadowRadius: CGFloat
    private let shadowYOffset: CGFloat

    public init(
        padding: CGFloat = DSSpacing.lg,
        cornerRadius: CGFloat = DSCorners.card,
        shadowOpacity: CGFloat = 0.04,
        shadowRadius: CGFloat = DSSpacing.sm,
        shadowYOffset: CGFloat = DSSpacing.xs,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowYOffset = shadowYOffset
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowYOffset)
        )
    }
}

/// Consistent section header used inside cards.
/// - Renders optional SF Symbol icon, uppercase small title, and an optional caption.
public struct SectionHeader: View {
    private let icon: String?
    private let title: String
    private let caption: String?

    public init(icon: String? = nil, title: String, caption: String? = nil) {
        self.icon = icon
        self.title = title
        self.caption = caption
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(DSColors.accent)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title.uppercased())
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Consistent small caption footer used under sections.
public struct SectionFooter: View {
    private let text: String
    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
