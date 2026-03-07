import SwiftUI

struct SettingsPanelView: View {
    @Binding var adminURLInput: String
    let resolvedAdminURL: String
    let isBusy: Bool
    let errorMessage: String?
    let model: SettingsPanelModel
    let onApply: () async -> Void
    let onReset: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SurfaceCard(title: model.sections[0].title) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.sections[0].description)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)

                        TextField("http://127.0.0.1:7777", text: $adminURLInput)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.statusColors.error.fill)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    SurfaceCard(title: model.sections[1].title) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.sections[1].description)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                            StatusPill(text: model.statusText, semanticColor: errorMessage == nil ? DesignTokens.statusColors.running : DesignTokens.statusColors.error)

                            HStack(spacing: 12) {
                                Button("Apply") {
                                    Task { await onApply() }
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .disabled(isBusy)

                                Button("Reset", action: onReset)
                                    .buttonStyle(.plain)
                                .focusable(false)
                                    .foregroundStyle(DesignTokens.textSecondary)
                                    .disabled(isBusy)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    SurfaceCard(title: model.sections[2].title) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.sections[2].description)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                            detailRow(label: "Current Endpoint", value: resolvedAdminURL)
                            detailRow(label: "Busy", value: isBusy ? "Yes" : "No")
                            detailRow(label: "Error", value: errorMessage ?? "-")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.textPrimary)
        }
    }
}
