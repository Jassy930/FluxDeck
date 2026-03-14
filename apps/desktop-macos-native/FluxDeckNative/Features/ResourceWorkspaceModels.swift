import Foundation

struct ProviderWorkspaceCard {
    let id: String
    let title: String
    let kindBadge: String
    let endpointText: String
    let modelCountText: String
    let statusText: String
    let healthStatusText: String
    let healthDetailText: String?

    static func make(provider: AdminProvider, healthStates: [AdminProviderHealthState] = []) -> ProviderWorkspaceCard {
        let modelCount = provider.models.count
        let modelCountText = modelCount == 1 ? "1 model" : "\(modelCount) models"
        let health = preferredHealthState(for: provider.id, states: healthStates)

        return ProviderWorkspaceCard(
            id: provider.id,
            title: provider.name,
            kindBadge: provider.kind.uppercased(),
            endpointText: provider.baseURL,
            modelCountText: modelCountText,
            statusText: provider.enabled ? "ENABLED" : "DISABLED",
            healthStatusText: health?.status.uppercased() ?? "HEALTHY",
            healthDetailText: health?.lastFailureReason
        )
    }
}

struct GatewayWorkspaceCard {
    let id: String
    let title: String
    let endpointText: String
    let runtimeBadge: String
    let providerText: String
    let activeProviderText: String
    let routeSummaryText: String
    let healthSummaryText: String
    let autoStartText: String
    let lastErrorText: String?

    static func make(gateway: AdminGateway) -> GatewayWorkspaceCard {
        let category = runtimeCategory(for: gateway)
        let routeSummary = gateway.routeTargets
            .sorted { $0.priority < $1.priority }
            .map { target in
                if let health = nonEmpty(target.healthStatus) {
                    return "\(target.providerId) [\(health)]"
                }
                return target.providerId
            }
            .joined(separator: " -> ")
        let summary = gateway.healthSummary.map { healthSummary in
            "\(healthSummary.healthyCount) healthy · \(healthSummary.degradedCount) degraded · \(healthSummary.unhealthyCount) unhealthy"
        } ?? "No health summary"

        return GatewayWorkspaceCard(
            id: gateway.id,
            title: gateway.name,
            endpointText: "\(gateway.listenHost):\(gateway.listenPort)",
            runtimeBadge: category.rawValue.uppercased(),
            providerText: gateway.defaultProviderId,
            activeProviderText: gateway.activeProviderId ?? "Idle",
            routeSummaryText: routeSummary.isEmpty ? gateway.defaultProviderId : routeSummary,
            healthSummaryText: summary,
            autoStartText: gateway.autoStart ? "ON" : "OFF",
            lastErrorText: gateway.lastError
        )
    }
}

private func preferredHealthState(
    for providerID: String,
    states: [AdminProviderHealthState]
) -> AdminProviderHealthState? {
    states.first(where: { $0.providerId == providerID && $0.scope == "global" })
        ?? states.first(where: { $0.providerId == providerID })
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    return value
}
