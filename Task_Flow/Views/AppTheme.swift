import SwiftUI

// MARK: - Design Tokens

enum AppTheme {
    enum Colors {
        static let badge = Color.primary.opacity(0.08)
        static let tagBackground = Color.accentColor.opacity(0.1)
        static let selectedBorder = Color.accentColor.opacity(0.6)
        static let addButtonTint = Color.accentColor.opacity(0.7)
    }

    enum Spacing {
        static let cardPadding: CGFloat = 12
        static let columnPadding: CGFloat = 10
        static let cardGap: CGFloat = 8
        static let columnGap: CGFloat = 14
    }

    enum Radius {
        static let card: CGFloat = 10
        static let column: CGFloat = 14
        static let tag: CGFloat = 6
        static let button: CGFloat = 8
    }

    enum Shadow {
        static let cardRadius: CGFloat = 2
        static let cardHoverRadius: CGFloat = 6
        static let cardOpacity: Double = 0.05
        static let cardHoverOpacity: Double = 0.1
    }
}

// MARK: - Liquid Glass

/// Apple-style Liquid Glass effect
/// Layers: base tint → material blur → specular highlight → outer stroke → shadow
struct LiquidGlass: ViewModifier {
    var cornerRadius: CGFloat
    var tintColor: Color?
    var isElevated: Bool
    var isInteractive: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    func body(content: Content) -> some View {
        content
            .background(glassBackground)
            .overlay(specularHighlight)
            .overlay(outerStroke)
            .shadow(
                color: .black.opacity(isElevated ? 0.15 : 0.06),
                radius: isElevated ? 20 : 10,
                y: isElevated ? 10 : 4
            )
            .shadow(
                color: .black.opacity(isElevated ? 0.08 : 0.03),
                radius: isElevated ? 2 : 1,
                y: 1
            )
    }

    // Layer 1: Tinted translucent background
    @ViewBuilder
    private var glassBackground: some View {
        ZStack {
            if let tint = tintColor {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(isDark ? 0.15 : 0.08))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.controlBackgroundColor).opacity(isDark ? 0.35 : 0.5))
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isDark ? 0.85 : 0.75)
        }
    }

    // Layer 2: Specular highlight — bright edge on top, fading downward
    private var specularHighlight: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(isDark ? 0.18 : 0.65), location: 0),
                        .init(color: Color.white.opacity(isDark ? 0.06 : 0.2), location: 0.25),
                        .init(color: Color.white.opacity(0), location: 0.55),
                        .init(color: Color.white.opacity(isDark ? 0.03 : 0.05), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.0
            )
            .padding(0.5)
    }

    // Layer 3: Outer edge definition
    private var outerStroke: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                isDark
                    ? Color.white.opacity(0.08)
                    : Color.black.opacity(0.06),
                lineWidth: 0.5
            )
    }
}

extension View {
    func liquidGlass(
        cornerRadius: CGFloat = AppTheme.Radius.column,
        tint: Color? = nil,
        elevated: Bool = false,
        interactive: Bool = false
    ) -> some View {
        modifier(LiquidGlass(
            cornerRadius: cornerRadius,
            tintColor: tint,
            isElevated: elevated,
            isInteractive: interactive
        ))
    }
}

// MARK: - Glass Card (for task cards — lighter treatment)

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.Radius.card
    var isHovering: Bool = false
    var isSelected: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isDark ? Color(.controlBackgroundColor).opacity(0.6) : Color.white.opacity(0.85))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.5)
                    )
            )
            .overlay(selectedOverlay)
            .overlay(glassEdge)
            .shadow(
                color: .black.opacity(isHovering ? AppTheme.Shadow.cardHoverOpacity : AppTheme.Shadow.cardOpacity),
                radius: isHovering ? AppTheme.Shadow.cardHoverRadius : AppTheme.Shadow.cardRadius,
                y: isHovering ? 3 : 1
            )
    }

    @ViewBuilder
    private var selectedOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.Colors.selectedBorder, lineWidth: 1.5)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.1 : 0.4),
                            Color.white.opacity(isDark ? 0.03 : 0.1),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
    }

    @ViewBuilder
    private var glassEdge: some View {
        if !isSelected {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04),
                    lineWidth: 0.5
                )
        }
    }
}

extension View {
    func glassCard(
        cornerRadius: CGFloat = AppTheme.Radius.card,
        isHovering: Bool = false,
        isSelected: Bool = false
    ) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, isHovering: isHovering, isSelected: isSelected))
    }
}
