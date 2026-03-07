import SwiftUI

struct TopModeBar: View {
    let title: String
    @Binding var selectedMode: AppMode
    let statusSummary: ShellStatusSummary

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Workspace")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(DesignTokens.textSecondary)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selectedMode == mode ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(modeBackground(for: mode))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .padding(4)
            .background(DesignTokens.surfaceSecondary.opacity(0.72))
            .overlay(
                Capsule()
                    .stroke(DesignTokens.borderSubtle.opacity(0.35), lineWidth: 1)
            )
            .clipShape(Capsule())

            HStack(spacing: 8) {
                StatusPill(text: statusSummary.connectionLabel, semanticColor: statusSummary.connectionColor)
                StatusPill(text: statusSummary.gatewayLabel, semanticColor: statusSummary.gatewayColor)
                StatusPill(text: statusSummary.errorLabel, semanticColor: statusSummary.errorColor)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(DesignTokens.surfacePrimary.opacity(0.82))
    }

    @ViewBuilder
    private func modeBackground(for mode: AppMode) -> some View {
        if selectedMode == mode {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
        } else {
            Color.clear
        }
    }
}
