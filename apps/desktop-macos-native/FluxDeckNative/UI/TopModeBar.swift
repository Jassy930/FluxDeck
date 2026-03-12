import SwiftUI

struct ShellToolbarModel {
    let title: String
    let endpointLabel: String
    let endpointValue: String
    let lastRefreshLabel: String?
    let isRefreshing: Bool
    let statusSummary: ShellStatusSummary

    static func make(
        title: String,
        adminBaseURL: String,
        lastRefreshText: String?,
        isRefreshing: Bool,
        statusSummary: ShellStatusSummary
    ) -> ShellToolbarModel {
        ShellToolbarModel(
            title: title,
            endpointLabel: "Admin",
            endpointValue: adminBaseURL,
            lastRefreshLabel: lastRefreshText.map { "Last refresh \($0)" },
            isRefreshing: isRefreshing,
            statusSummary: statusSummary
        )
    }
}

struct TopModeBar: View {
    let model: ShellToolbarModel
    @Binding var selectedMode: AppMode
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Workspace")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(DesignTokens.textSecondary)

                    Text(model.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                }

                HStack(spacing: 8) {
                    Text(model.endpointLabel)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(DesignTokens.textSecondary)

                    Text(model.endpointValue)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textPrimary.opacity(0.92))
                        .lineLimit(1)
                        .layoutPriority(1)

                    if let lastRefreshLabel = model.lastRefreshLabel {
                        Circle()
                            .fill(DesignTokens.borderSubtle.opacity(0.9))
                            .frame(width: 4, height: 4)

                        Text(lastRefreshLabel)
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            HStack(spacing: 10) {
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
                    StatusPill(text: model.statusSummary.connectionLabel, semanticColor: model.statusSummary.connectionColor)
                    StatusPill(text: model.statusSummary.gatewayLabel, semanticColor: model.statusSummary.gatewayColor)
                    StatusPill(text: model.statusSummary.errorLabel, semanticColor: model.statusSummary.errorColor)
                }

                Button(action: onRefresh) {
                    HStack(spacing: 6) {
                        if model.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }

                        Text("Refresh")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(DesignTokens.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DesignTokens.surfaceSecondary.opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DesignTokens.borderSubtle.opacity(0.45), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(model.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
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
