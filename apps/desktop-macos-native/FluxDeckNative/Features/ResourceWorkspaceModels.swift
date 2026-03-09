import Foundation

struct ProviderWorkspaceCard {
    let id: String
    let title: String
    let kindBadge: String
    let endpointText: String
    let modelCountText: String
    let statusText: String

    static func make(provider: AdminProvider) -> ProviderWorkspaceCard {
        let modelCount = provider.models.count
        let modelCountText = modelCount == 1 ? "1 model" : "\(modelCount) models"

        return ProviderWorkspaceCard(
            id: provider.id,
            title: provider.name,
            kindBadge: provider.kind.uppercased(),
            endpointText: provider.baseURL,
            modelCountText: modelCountText,
            statusText: provider.enabled ? "ENABLED" : "DISABLED"
        )
    }
}

struct GatewayWorkspaceCard {
    let id: String
    let title: String
    let endpointText: String
    let runtimeBadge: String
    let providerText: String
    let autoStartText: String
    let lastErrorText: String?

    static func make(gateway: AdminGateway) -> GatewayWorkspaceCard {
        let category = runtimeCategory(for: gateway)

        return GatewayWorkspaceCard(
            id: gateway.id,
            title: gateway.name,
            endpointText: "\(gateway.listenHost):\(gateway.listenPort)",
            runtimeBadge: category.rawValue.uppercased(),
            providerText: gateway.defaultProviderId,
            autoStartText: gateway.autoStart ? "ON" : "OFF",
            lastErrorText: gateway.lastError
        )
    }
}
