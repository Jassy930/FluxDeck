import SwiftUI

struct SettingsPanelView: View {
    @Environment(\.locale) private var locale

    @Binding var adminURLInput: String
    @Binding var selectedLanguage: AppLanguage
    let resolvedAdminURL: String
    let isBusy: Bool
    let errorMessage: String?
    let model: SettingsPanelModel
    let onApply: () async -> Void
    let onReset: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SurfaceCard(title: L10n.string(model.sections[0].titleKey, locale: locale)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string(model.sections[0].descriptionKey, locale: locale))
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
                    SurfaceCard(title: L10n.string(model.sections[1].titleKey, locale: locale)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.string(model.sections[1].descriptionKey, locale: locale))
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                            StatusPill(
                                text: L10n.settingsStatus(model.status, locale: locale),
                                semanticColor: errorMessage == nil ? DesignTokens.statusColors.running : DesignTokens.statusColors.error
                            )

                            HStack(spacing: 12) {
                                Button(L10n.string(L10n.settingsActionApply, locale: locale)) {
                                    Task { await onApply() }
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .disabled(isBusy)

                                Button(L10n.string(L10n.settingsActionReset, locale: locale), action: onReset)
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                    .foregroundStyle(DesignTokens.textSecondary)
                                    .disabled(isBusy)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    SurfaceCard(title: L10n.string(model.sections[2].titleKey, locale: locale)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.string(model.sections[2].descriptionKey, locale: locale))
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                            detailRow(label: L10n.string(L10n.settingsDiagnosticsCurrentEndpoint, locale: locale), value: resolvedAdminURL)
                            detailRow(label: L10n.string(L10n.settingsDiagnosticsBusy, locale: locale), value: L10n.string(isBusy ? L10n.commonValueYes : L10n.commonValueNo, locale: locale))
                            detailRow(label: L10n.string(L10n.settingsDiagnosticsError, locale: locale), value: errorMessage ?? "-")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                SurfaceCard(title: L10n.string(model.languageSection.titleKey, locale: locale)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string(model.languageSection.descriptionKey, locale: locale))
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)

                        Picker(L10n.string(model.languageSection.titleKey, locale: locale), selection: $selectedLanguage) {
                            ForEach(model.languageOptions) { option in
                                Text(option.title)
                                    .tag(option.language)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(isBusy)
                    }
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
