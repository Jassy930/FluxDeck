import SwiftUI

struct DesignTokens {
    struct CornerRadius {
        let window: CGFloat
        let panel: CGFloat
        let card: CGFloat
        let pill: CGFloat
    }

    struct SemanticColor {
        let fill: Color
        let glow: Color
        let accessibilityName: String
    }

    struct StatusColors {
        let running: SemanticColor
        let warning: SemanticColor
        let error: SemanticColor
        let inactive: SemanticColor
    }

    static let cornerRadius = CornerRadius(
        window: 26,
        panel: 18,
        card: 18,
        pill: 999
    )

    static let statusColors = StatusColors(
        running: SemanticColor(
            fill: Color(red: 0.29, green: 0.87, blue: 0.50),
            glow: Color(red: 0.29, green: 0.87, blue: 0.50, opacity: 0.24),
            accessibilityName: "running"
        ),
        warning: SemanticColor(
            fill: Color(red: 1.00, green: 0.62, blue: 0.26),
            glow: Color(red: 1.00, green: 0.62, blue: 0.26, opacity: 0.22),
            accessibilityName: "warning"
        ),
        error: SemanticColor(
            fill: Color(red: 1.00, green: 0.36, blue: 0.45),
            glow: Color(red: 1.00, green: 0.36, blue: 0.45, opacity: 0.24),
            accessibilityName: "error"
        ),
        inactive: SemanticColor(
            fill: Color(red: 0.44, green: 0.46, blue: 0.51),
            glow: Color(red: 0.44, green: 0.46, blue: 0.51, opacity: 0.16),
            accessibilityName: "inactive"
        )
    )

    static let workbenchBackground = Color(red: 0.07, green: 0.08, blue: 0.09)
    static let surfacePrimary = Color(red: 0.11, green: 0.12, blue: 0.13)
    static let surfaceSecondary = Color(red: 0.14, green: 0.15, blue: 0.17)
    static let borderSubtle = Color(red: 0.17, green: 0.18, blue: 0.21)
    static let textPrimary = Color(red: 0.95, green: 0.96, blue: 0.96)
    static let textSecondary = Color(red: 0.60, green: 0.63, blue: 0.67)
}
