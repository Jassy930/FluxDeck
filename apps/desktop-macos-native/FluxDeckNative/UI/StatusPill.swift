import SwiftUI

struct StatusPill: View {
    let text: String
    let semanticColor: DesignTokens.SemanticColor

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(semanticColor.fill)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(DesignTokens.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(semanticColor.glow)
        .overlay(
            Capsule()
                .stroke(semanticColor.fill.opacity(0.35), lineWidth: 1)
        )
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text) \(semanticColor.accessibilityName)")
    }
}
