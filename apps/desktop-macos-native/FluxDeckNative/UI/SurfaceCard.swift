import SwiftUI

struct SurfaceCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surfaceSecondary.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius.card, style: .continuous)
                .stroke(DesignTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius.card, style: .continuous))
    }
}
