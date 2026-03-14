import Foundation

struct ProviderWorkspaceCard {
    let id: String
    let title: String
    let kindBadge: String
    let endpointText: String
    let modelCount: Int
    let isEnabled: Bool
    let healthStatus: String
    let healthDetailText: String?

    static func make(provider: AdminProvider, healthStates: [AdminProviderHealthState] = []) -> ProviderWorkspaceCard {
        let health = preferredHealthState(for: provider.id, states: healthStates)

        return ProviderWorkspaceCard(
            id: provider.id,
            title: provider.name,
            kindBadge: provider.kind.uppercased(),
            endpointText: provider.baseURL,
            modelCount: provider.models.count,
            isEnabled: provider.enabled,
            healthStatus: normalizedHealthStatus(health?.status),
            healthDetailText: nonEmpty(health?.lastFailureReason)
        )
    }
}

struct GatewayRouteTargetSummary: Equatable {
    let providerId: String
    let healthStatus: String?
}

struct GatewayWorkspaceCard {
    let id: String
    let title: String
    let endpointText: String
    let runtimeState: GatewayRuntimeCategory
    let providerText: String
    let activeProviderText: String?
    let routeTargets: [GatewayRouteTargetSummary]
    let healthSummary: AdminGatewayHealthSummary?
    let autoStartEnabled: Bool
    let lastErrorText: String?

    static func make(gateway: AdminGateway) -> GatewayWorkspaceCard {
        let category = runtimeCategory(for: gateway)
        let routeTargets = gateway.routeTargets
            .sorted { $0.priority < $1.priority }
            .map { target in
                GatewayRouteTargetSummary(
                    providerId: target.providerId,
                    healthStatus: nonEmpty(target.healthStatus).map(normalizedHealthStatus)
                )
            }

        return GatewayWorkspaceCard(
            id: gateway.id,
            title: gateway.name,
            endpointText: "\(gateway.listenHost):\(gateway.listenPort)",
            runtimeState: category,
            providerText: gateway.defaultProviderId,
            activeProviderText: nonEmpty(gateway.activeProviderId),
            routeTargets: routeTargets,
            healthSummary: gateway.healthSummary,
            autoStartEnabled: gateway.autoStart,
            lastErrorText: nonEmpty(gateway.lastError)
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

private func normalizedHealthStatus(_ rawValue: String?) -> String {
    let normalized = rawValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    switch normalized {
    case "degraded":
        return "degraded"
    case "unhealthy":
        return "unhealthy"
    case "probing":
        return "probing"
    case "healthy":
        return "healthy"
    default:
        return "unknown"
    }
}
