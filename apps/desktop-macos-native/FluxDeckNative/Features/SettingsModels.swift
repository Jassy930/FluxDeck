import Foundation

struct SettingsPanelSection: Equatable {
    let titleKey: String
    let descriptionKey: String
}

enum SettingsPanelStatus: Equatable {
    case needsAttention
    case refreshing
    case notConfigured
    case ready
}

struct SettingsLanguageOption: Equatable, Identifiable {
    let language: AppLanguage
    let title: String

    var id: String { language.id }
}

struct SettingsPanelModel {
    let sections: [SettingsPanelSection]
    let status: SettingsPanelStatus
    let languageSection: SettingsPanelSection
    let languageOptions: [SettingsLanguageOption]

    static func make(
        adminBaseURL: String,
        isLoading: Bool,
        hasError: Bool,
        selectedLanguage: AppLanguage,
        locale: Locale = .autoupdatingCurrent
    ) -> SettingsPanelModel {
        _ = selectedLanguage

        let status: SettingsPanelStatus
        if hasError {
            status = .needsAttention
        } else if isLoading {
            status = .refreshing
        } else {
            status = adminBaseURL.isEmpty ? .notConfigured : .ready
        }

        return SettingsPanelModel(
            sections: [
                SettingsPanelSection(
                    titleKey: L10n.settingsSectionAdminApiTitle,
                    descriptionKey: L10n.settingsSectionAdminApiDescription
                ),
                SettingsPanelSection(
                    titleKey: L10n.settingsSectionRefreshSyncTitle,
                    descriptionKey: L10n.settingsSectionRefreshSyncDescription
                ),
                SettingsPanelSection(
                    titleKey: L10n.settingsSectionDiagnosticsTitle,
                    descriptionKey: L10n.settingsSectionDiagnosticsDescription
                )
            ],
            status: status,
            languageSection: SettingsPanelSection(
                titleKey: L10n.settingsLanguageTitle,
                descriptionKey: L10n.settingsLanguageDescription
            ),
            languageOptions: [
                SettingsLanguageOption(language: .system, title: L10n.string(L10n.settingsLanguageOptionSystem, locale: locale)),
                SettingsLanguageOption(language: .english, title: L10n.string(L10n.settingsLanguageOptionEnglish, locale: locale)),
                SettingsLanguageOption(language: .simplifiedChinese, title: L10n.string(L10n.settingsLanguageOptionSimplifiedChinese, locale: locale))
            ]
        )
    }
}

struct LogDetailCardModel {
    let requestID: String
    let routeText: String
    let modelText: String
    let statusText: String
    let latencyText: String
    let errorText: String
    let createdAtText: String

    static func make(log: AdminLog) -> LogDetailCardModel {
        LogDetailCardModel(
            requestID: log.requestID,
            routeText: "\(log.gatewayID) → \(log.providerID)",
            modelText: log.modelDisplayText,
            statusText: "\(log.statusCode)",
            latencyText: "\(log.latencyMs) ms",
            errorText: log.errorSummaryText,
            createdAtText: log.createdAt
        )
    }
}
