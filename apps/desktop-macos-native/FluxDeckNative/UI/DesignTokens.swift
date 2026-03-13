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
    static let topologyStageBackground = Color(red: 0.08, green: 0.09, blue: 0.10)
    static let topologyRail = Color(red: 0.10, green: 0.11, blue: 0.13, opacity: 0.82)
    static let topologyAnchorFill = Color(red: 0.12, green: 0.13, blue: 0.15, opacity: 0.95)
    static let topologyTooltipBackground = Color(red: 0.10, green: 0.11, blue: 0.13, opacity: 0.98)
    static let borderSubtle = Color(red: 0.17, green: 0.18, blue: 0.21)
    static let textPrimary = Color(red: 0.95, green: 0.96, blue: 0.96)
    static let textSecondary = Color(red: 0.60, green: 0.63, blue: 0.67)

    private static let topologyRankPalette: [SemanticColor] = [
        statusColors.running,
        SemanticColor(
            fill: Color(red: 0.29, green: 0.81, blue: 0.93),
            glow: Color(red: 0.29, green: 0.81, blue: 0.93, opacity: 0.20),
            accessibilityName: "cyan"
        ),
        statusColors.warning,
        SemanticColor(
            fill: Color(red: 0.48, green: 0.60, blue: 0.96),
            glow: Color(red: 0.48, green: 0.60, blue: 0.96, opacity: 0.18),
            accessibilityName: "indigo"
        )
    ]

    static func topologyModelColor(for modelName: String, rankedIndex: Int?) -> SemanticColor {
        if modelName == "Other" || modelName == "unknown" {
            return statusColors.inactive
        }

        if let rankedIndex {
            return topologyRankPalette[rankedIndex % topologyRankPalette.count]
        }

        return topologyModelColor(for: modelName)
    }

    static func topologyModelColor(for modelName: String) -> SemanticColor {
        switch modelName {
        case "m1", "glm-4.5", "gpt-4o", "gpt-4.1", "gpt-4o-mini":
            return statusColors.running
        case "m2", "claude-3-7-sonnet", "claude-3.7-sonnet", "claude-sonnet-4":
            return SemanticColor(
                fill: Color(red: 0.29, green: 0.81, blue: 0.93),
                glow: Color(red: 0.29, green: 0.81, blue: 0.93, opacity: 0.20),
                accessibilityName: "cyan"
            )
        case "m3", "gemini-2.0-flash", "gemini-2.5-pro":
            return statusColors.warning
        case "Other", "unknown":
            return statusColors.inactive
        default:
            return SemanticColor(
                fill: Color(red: 0.48, green: 0.60, blue: 0.96),
                glow: Color(red: 0.48, green: 0.60, blue: 0.96, opacity: 0.18),
                accessibilityName: "indigo"
            )
        }
    }
}
