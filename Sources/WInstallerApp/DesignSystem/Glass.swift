import SwiftUI

// MARK: - Liquid Glass primitives
//
// These helpers are the single place where the app opts into macOS 26's Liquid
// Glass. On macOS 26 (and when Reduce Transparency is off) surfaces use
// `.glassEffect`; everywhere else they fall back to native system materials so
// the app still looks at home on macOS 15. Building requires the macOS 26 SDK
// (Xcode 26+); the deployment target stays at macOS 15.

/// Wraps content in a rounded glass (or material) surface used for the app's
/// cards and panels.
struct GlassCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *), !reduceTransparency {
            content
                .padding(Space.lg)
                .glassEffect(glass(with: tint), in: shape)
        } else {
            content
                .padding(Space.lg)
                .background(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
        }
    }

    @available(macOS 26.0, *)
    private func glass(with tint: Color?) -> Glass {
        if let tint { return Glass.regular.tint(tint) }
        return Glass.regular
    }
}

/// Like `GlassCardModifier` but without internal padding — for fixed-size chips
/// such as the step-header icon.
struct GlassChipModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
        }
    }
}

extension View {
    /// A rounded glass card. Adds internal padding; wrap content directly.
    func glassCard(cornerRadius: CGFloat = Radius.card, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// A glass surface with no added padding, sized by the caller's frame.
    func glassChip(cornerRadius: CGFloat = Radius.control) -> some View {
        modifier(GlassChipModifier(cornerRadius: cornerRadius))
    }

    /// Prominent primary action (Continue, Erase). Glass on macOS 26, bordered
    /// prominent otherwise.
    @ViewBuilder
    func primaryGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Secondary action. Glass on macOS 26, bordered otherwise.
    @ViewBuilder
    func secondaryGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

/// Groups multiple glass surfaces so they blend and morph together. A no-op
/// passthrough on macOS 15.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = Space.md, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
