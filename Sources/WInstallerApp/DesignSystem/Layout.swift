import SwiftUI

/// Spacing scale from `DESIGN_SYSTEM.md`. Using named steps keeps padding
/// consistent instead of scattering magic numbers across views.
enum Space {
    /// 4 — tight icon-text gap.
    static let xs: CGFloat = 4
    /// 8 — compact control padding.
    static let sm: CGFloat = 8
    /// 12 — grouped control gap.
    static let md: CGFloat = 12
    /// 16 — section gap.
    static let lg: CGFloat = 16
    /// 24 — major content gap.
    static let xl: CGFloat = 24
    /// 32 — screen-level spacing.
    static let xxl: CGFloat = 32
}

/// Corner radii. Cards stay at 12 or below per the design system; the system
/// provides its own shape for native controls.
enum Radius {
    static let card: CGFloat = 12
    static let control: CGFloat = 8
    static let pill: CGFloat = 999
}
