import Foundation

struct SettingsPanelSection: Equatable {
    let title: String
    let description: String
}

struct SettingsPanelModel {
    let sections: [SettingsPanelSection]
    let statusText: String

    static func make(adminBaseURL: String, isLoading: Bool, hasError: Bool) -> SettingsPanelModel {
        let statusText: String
        if hasError {
            statusText = "Needs attention"
        } else if isLoading {
            statusText = "Refreshing"
        } else {
            statusText = adminBaseURL.isEmpty ? "Not configured" : "Ready"
        }

        return SettingsPanelModel(
            sections: [
                SettingsPanelSection(title: "Admin API", description: "Configure the fluxd Admin API endpoint used by the native shell."),
                SettingsPanelSection(title: "Refresh & Sync", description: "Apply, refresh and reset connection settings without leaving the workbench."),
                SettingsPanelSection(title: "Diagnostics", description: "Review current endpoint and shell state for troubleshooting.")
            ],
            statusText: statusText
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
